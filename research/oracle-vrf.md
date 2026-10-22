# Oracle VRF Construction on Aleo

Ticket: [#11](https://github.com/mangekyou-labs/aleo-vrf/issues/11). Parent map: [#1](https://github.com/mangekyou-labs/aleo-vrf/issues/1). Terms (Beacon, Round, Consumer program, Randomness request, Relayer, Fulfillment, Delivery) are used as defined in [GLOSSARY.md](../GLOSSARY.md). "Oracle" here means the Relayer holding a VRF key, as in the Soroban VRF reference architecture. Leo 4 terms: `fn` = off-chain proved function, `final` = on-chain finalize. The prototype is written in Leo 3.4.0 syntax (`transition` / `async function`), which compiles to the same Aleo instructions.

Researched 2026-10-22.

## Verdict

| Question | Answer | Basis |
|---|---|---|
| Can an oracle-keyed unique-output function be built on Aleo cheaply? | **Yes.** Proof-as-VRF costs about **+9,100 constraints** over an I/O baseline. Its `final` costs about **14,330 microcredits**. | Measured (`leo synthesize`). The `final` cost is computed from `cost.rs` constants, not executed on-chain. |
| ECVRF-style DLEQ checked in `final`? | **Also feasible.** It costs about **156,600 microcredits**, which is 3.9% of the 4,000,000 per-function cap. | Instruction list measured from the compiled `.aleo`. The price is computed from `cost.rs` constants. |
| Which hash-to-group? | **Poseidon (`Poseidon2::hash_to_group`) only.** Not BHP. | snarkVM source. BHP hash-to-group is a linear Pedersen sum, so it breaks output secrecy whenever `gamma` is revealed. |
| Should drand be in `alpha`? | **No.** On Aleo, drand data supplied by the oracle cannot be verified. Putting it in `alpha`, or in the final output, lets the oracle grind freely. | Threat analysis below. |
| Recommended construction | **Proof-as-VRF with Poseidon.** `alpha` is fixed in the request's `final` and includes `rand.chacha` drawn at request time. The pk is snapshotted at request. No drand in the on-chain path. | Cheapest measured option, and it keeps `gamma` private. |

**What it buys.** Uniqueness: the oracle cannot choose among outputs. Output secrecy: no one but the oracle knows `beta` before fulfillment. Both hold on Aleo under the recommended `alpha`.

**What it does not buy.**
- Input unpredictability **against the oracle**. The oracle learns `beta` as soon as the request finalizes.
- Protection against **selective withholding**.
- Any verifiable link to drand.

This is a trusted-key VRF. It is not a public-randomness beacon. Whether to adopt it is the call for [Oracle VRF Layer: Adopt or Not (#12)](https://github.com/mangekyou-labs/aleo-vrf/issues/12).

## Measurements

- **Setup:** Leo 3.4.0, `leo synthesize oracle_vrf.aleo --local --network testnet`, Apple M4. Source: [`oracle-vrf-prototype/oracle_vrf/src/main.leo`](oracle-vrf-prototype/oracle_vrf/src/main.leo).
- **Common shape:** every transition takes `public alpha: field, public pk: group, private sk: scalar` and returns `public field`. `dleq_fulfill` is the exception: it takes `alpha, gamma, c, s`, all public, and does its work in `final`.
- **Marginal** is the measured count minus `io_baseline`.

| Transition | What it proves | Constraints | Marginal |
|---|---|---|---|
| `io_baseline` | returns `alpha` | 14,058 | 0 |
| `key_check` | `sk·G == pk` (fixed-base mul) | 16,564 | 2,506 |
| `vrf_psd2` | key check, then `h = Poseidon2::hash_to_group(alpha)`, `gamma = sk·h`, `beta = Poseidon2::hash_to_field(gamma)` | 23,136 | **9,078** |
| `vrf_bhp256` | the same, with BHP256 (comparison only) | 23,560 | 9,502 |
| `vrf_psd2_fulfill` | `vrf_psd2`, plus a future to `final` that checks pk and pending `alpha` | 24,139 | 10,081 |
| `dleq_fulfill` | no in-circuit crypto; passes `(alpha, gamma, c, s)` to `final` | 14,774 | 716 |

Sanity runs with `leo run`:
- `vrf_psd2(7field, G, 1scalar)` returns a field.
- With a wrong key (`2scalar` against `pk = G`), it fails at `assert.eq r3 r1`.

Proving time was **not measured**: `leo execute` needs the testnet height endpoint, which was unreachable from the sandbox. The circuit is about 1.6x the I/O baseline. The drand research measured 7–14 s wall clock for comparable small circuits, so expect the same order of magnitude. This is an estimate.

**Deployment synthesis fee** is 25 microcredits per constraint (`SYNTHESIS_FEE_MULTIPLIER`), so `vrf_psd2_fulfill` adds about 0.60 credits to deployment. That uses 0.6% of the 2^22 per-deployment constraint cap.

### `final` cost (computed from `cost.rs` @ 038b3ea)

Sizes:
- `field`, `group` and `scalar` are 32 B. A group serializes as its x-coordinate (`console/types/group/src/size_in_bytes.rs`).
- `bool` is 1 B.
- The struct `DleqTranscript` is 15 B of name plus 5 × 32 B, which is 175 B.

**Proof-as-VRF `final`** (`finalize vrf_psd2_fulfill`, 5 commands):

| Command | Cost (µc) |
|---|---|
| `get oracle_pk[true]` | 1,500 + 10·1 = 1,510 |
| `assert.eq` | 500 |
| `get pending_alpha[alpha]` | 1,500 + 10·32 = 1,820 |
| `assert.eq` | 500 |
| `remove` | 10,000 |
| **Total** | **14,330** |

**DLEQ `final`** (`finalize dleq_fulfill`, 13 commands, from `build/main.aleo`):

| Command | Cost (µc) |
|---|---|
| 2 × `get` | 1,510 + 1,820 |
| `assert.eq` ×2 | 1,000 |
| `hash.psd2 alpha into group` | 40,000 + 75·32 = 42,400 |
| `mul` (group×scalar) ×4 | 40,000 |
| `sub` ×2 | 1,000 |
| `cast` into `DleqTranscript` | 500 + 30·175 = 5,750 |
| `hash.psd4 transcript into scalar` | 40,000 + 75·175 = 53,125 |
| `remove` | 10,000 |
| **Total** | **156,605** (3.9% of 4,000,000) |

Hash costs depend only on input size. There is no surcharge for a group destination (`cost.rs` `HashPSD2` arm).

## Constructions

### (a) Proof-as-VRF (recommended)

```
fn fulfill(public alpha, public pk, private sk) -> public beta:
    assert sk·G == pk
    gamma = sk · Poseidon2::hash_to_group(alpha)
    beta  = Poseidon2::hash_to_field(DOMAIN_BETA, gamma)
final: assert pk == pk_snapshot[request]; assert alpha == stored_alpha[request]; consume request
```

The transaction's Varuna proof is the VRF proof. `gamma` never leaves the prover.

Why it is unique:
- `scalar` is canonical mod the subgroup order r, and `sk·G == pk` fixes `sk`.
- `Poseidon2::hash_to_group` returns a prime-order-subgroup point. snarkVM's tests assert it is on the curve, in the subgroup, non-zero and not the generator.
- So `gamma`, and therefore `beta`, is a function of `(pk, alpha)` alone.
- There is no cofactor or encoding malleability: every `group` value is checked into the subgroup on decode (`from_x_coordinate.rs`: "always enforced to be on the curve and in the correct subgroup").

**Caveat (private input ciphertexts).** Aleo writes private transition inputs into the transaction as ciphertexts under the transition view key. Anyone holding the oracle account's **view key** can decrypt `sk` from every fulfillment. The VRF key's security is therefore capped by the view-key custody of the oracle account. Use a dedicated account and never share its view key.

The pseudocode includes `DOMAIN_BETA`. The prototype omits it, which does not change the constraint count materially.

### (b) ECVRF-style DLEQ in `final`

The oracle publishes `gamma, c, s`. Then `final` recomputes:
- `u = s·G − c·pk`
- `v = s·H(alpha) − c·gamma`
- `c' = Poseidon4::hash_to_scalar(H, pk, gamma, u, v)`

and asserts `c == c'`. It works and is cheap enough.

It is still worse than (a):
- It costs about 11x more in `final`.
- It publishes `gamma`.
- The off-chain prover must reproduce snarkVM's Poseidon `hash_to_group` and `hash_to_scalar` bit-for-bit.
- It is **not** RFC 9381 ECVRF, because the curve and hashes differ. There is no off-the-shelf library or test vectors, so the gain in auditability is small.

### Hash-to-group choice: Poseidon, never BHP

BHP `hash_to_group` (`console/algorithms/src/bhp/hasher/hash_uncompressed.rs`) is a windowed Pedersen sum: `H(alpha) = Σ_w s_w(alpha)·G_w`. The bases `G_w` are public, and the coefficients `s_w` are computed publicly from the bits of `alpha`. So `sk·H(alpha) = Σ s_w(alpha)·(sk·G_w)`.

An observer who sees `gamma` for as many alphas as there are windows can solve for every `sk·G_w`. They can then compute `gamma`, and so `beta`, for any future `alpha`, and output secrecy is gone. In (a) `gamma` is hidden, so BHP would not leak directly, but it removes defense in depth for no gain: it costs 424 more constraints than Poseidon.

Poseidon `hash_to_group` (`console/algorithms/src/poseidon/hash_to_group.rs`) is `Elligator2(h0) + Elligator2(h1)` over two Poseidon outputs, which is a random-oracle-style hash-to-curve. Keccak and SHA-3 `hash_to_group` go through BHP internally (`synthesizer/program/src/logic/instruction/operation/hash.rs`), so they are excluded too.

## Threat analysis: `alpha` compositions

The actors are:
- **O:** oracle/Relayer, holding `sk`.
- **R:** requester (the Consumer program and its user).
- **V:** validators (the block proposer).

"Grind" means choosing among several candidate outputs.

### Entropy available in `final` (from source)

- `final` operands are `block.height`, `block.timestamp`, `network.id`, program metadata and mapping state. **There is no block-hash operand** (`synthesizer/program/src/logic/instruction/operand/mod.rs`).
- `rand.chacha` in `final` is seeded with:
  - the block's `random_seed`, which is `BHP768(block_round, height, cumulative_weight, cumulative_proof_target, previous_block_hash, timestamp)` (`finalize_global_state/mod.rs`)
  - the transition id
  - a nonce
  - optional seeds

  R cannot know the cumulative weight, proof target or timestamp of the block that will include its transaction, so R cannot predict this value at submission. V knows it while building the block and can bias it weakly, for example through the timestamp or which transactions it includes. This is reasoning from source, not measured.

### Compositions

| `alpha` | O grinds? | O early knowledge | R predicts / grinds? | V influence | Verdict |
|---|---|---|---|---|---|
| **A1:** includes unverified drand (as in Soroban: `H(request_id, drand_randomness)` supplied at fulfillment) | **Yes, without limit.** O picks any "drand" value, since nothing on-chain checks it. Uniqueness is void. | Learns `beta` at fulfillment | No | None | **Reject.** It is strictly worse than having no drand. |
| **A1′:** A1 plus an off-chain audit (O publishes the drand signature; anyone checks it against the drand pk off-chain) | Grinding is **detectable after the fact**, not prevented | Same as A1 | No | None | Fraud detection only. It needs a slashing or reputation mechanism that does not exist on-chain. |
| **A2:** request-time data only, R-chosen (`request_id`, `consumer`, `tag`, height at request) | No | Learns `beta` once the request is finalized | R cannot predict without `sk`. **R + O colluding** can preview `beta` for each candidate `tag` before submitting, which is offline grinding. | None | Acceptable only if O and R never collude |
| **A3 (recommended):** `alpha = Poseidon(DOMAIN_ALPHA, request_id, consumer, tag, rand.chacha)`, drawn and stored in the request's `final` | No | Learns `beta` once the request is finalized | R cannot predict `alpha` before inclusion, so even R + O collusion cannot grind offline. After inclusion, `alpha` is fixed. | V knows `alpha`, but cannot compute `beta` without `sk`. **V + O colluding** could try alternative blocks or timestamps, a bounded and costly grind. | Best available |
| **A4:** hybrid output `final = H(beta_vrf, drand_randomness)`, as the map's Round Binding output would become if the layer were bolted onto it | **Yes, without limit,** through a fake drand value | — | No | None | **Reject**, for the same reason as A1 |

Constraints that apply to every composition:
- **Snapshot pk per request.** If O can rotate the key between request and fulfillment, O can pick among the `beta` values of several keys. That is grinding by key rotation. Store `pk` (or a key epoch) in the request and check that one in `final`. Rotation then only affects new requests.
- **No cancellation or refund before timeout.** Otherwise R + O (who knows `beta`) can abort unfavourable outcomes.
- **Selective withholding** is not prevented. O knows `beta` and can decline to fulfil, and the timeout fires. The map's "timeout, no re-roll" rule must hold, and the Consumer program must not get a favourable fallback on timeout. Deterring withholding needs economics (a bond or reputation), not cryptography.

## Soroban reference §6.1 / §6.2 guarantees on Aleo

| Reference guarantee | On Aleo | Why |
|---|---|---|
| §6.1.1 Input unpredictability (future drand round; nobody knows `alpha` at request time) | **Does not hold as specified.** Partially replaced. | drand cannot be verified on-chain (#3), so a drand-based `alpha` is supplied by O and can be ground. With A3, R cannot predict `alpha`, but V knows it at block time and O knows `beta` once it is fixed. |
| §6.1.2 Output secrecy (only O can compute `beta` before fulfillment) | **Holds** | `gamma` stays private in (a). If (b) is used, Poseidon hash-to-group prevents BHP-style extrapolation. |
| §6.2 Uniqueness / no nonce grinding | **Holds only if `alpha` and `pk` are fixed on-chain before O acts** (A2/A3 plus pk snapshot) | Breaks under A1/A4, or with key rotation that has no snapshot |
| Verifiable link to the drand Beacon | **Does not hold** | No pairing or BLS12-381 support (#3) |
| Liveness / withholding | Same as the reference: not prevented | Timeout with no re-roll, plus economics |

## Implications for the map (for #12 to decide, not decided here)

- If the layer is adopted with A3, drand **leaves the on-chain path**. The service becomes "trusted-key VRF with on-chain uniqueness and output secrecy" rather than "drand relay". That conflicts with the map's current "service holds no key" stance and with the Round Binding output formula, which hashes the beacon signature.
- Keeping drand and adding the layer as A4 adds a key without adding security.
- Not adopting keeps the trusted-relay drand path decided under #6. Output secrecy then does not hold: anyone can compute the output from the public drand round.

## Caveats

- Proving time and `final` microcredit costs were not measured on a live network. Constraint counts were measured, and the `final` costs were computed from source constants at the pinned commit.
- Leo 3.4.0 was used. Leo 4 `fn`/`final` lowers to the same instructions, but counts may shift slightly with compiler changes.
- `rand.chacha`'s unpredictability to R and V's bias are reasoned from the seed preimage. They are not measured or formally analysed.
- The prototype's `final` omits request bookkeeping such as fees, callbacks and the pk epoch. Those add mapping operations at about 1.5k–10k µc each.

## Sources

All snarkVM paths are at [aleo-labs-protocol/snarkVM @ 038b3ea](https://github.com/aleo-labs-protocol/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48):
- `synthesizer/process/src/cost.rs`: finalize costs (`HASH_PSD_*`, `MAPPING_BASE_COST_V2`, `SET_BASE_COST`, `CAST_*`, `Mul` on group/scalar = 10,000, `TRANSACTION_SPEND_LIMIT` via `console/network/src/lib.rs`)
- `console/algorithms/src/poseidon/hash_to_group.rs`: Poseidon hash-to-group (Elligator2 × 2) and its subgroup tests
- `console/algorithms/src/bhp/hash_uncompressed.rs`, `console/algorithms/src/bhp/hasher/hash_uncompressed.rs`: BHP is a linear windowed Pedersen sum
- `synthesizer/program/src/logic/instruction/operation/hash.rs`: opcode-to-hasher mapping (Keccak/SHA-3 `hash_to_group` goes through BHP)
- `console/types/group/src/from_x_coordinate.rs`, `size_in_bytes.rs`: subgroup enforcement on decode; 32 B group
- `synthesizer/program/src/logic/instruction/operand/mod.rs`: `final` operands (no block hash)
- `synthesizer/program/src/logic/command/rand_chacha.rs`, `synthesizer/program/src/logic/finalize_global_state/mod.rs`: `rand.chacha` seed preimage

Aleo docs (local copy, `.claude/skills/aleo-docs/references/leo/language/operators/cryptographic_operators.md`): `ChaCha::rand_*` is validator-supplied randomness, available only in `final`; there is no pairing operator.

Prior research: [`research/drand-verification.md`](https://github.com/mangekyou-labs/aleo-vrf/blob/research/drand-verification/research/drand-verification.md) (#3), for the limits and the drand-unverifiability result.
