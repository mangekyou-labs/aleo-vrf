# drand Verification Feasibility on Aleo

Ticket: [#3](https://github.com/mangekyou-labs/aleo-vrf/issues/3). Parent map: [#1](https://github.com/mangekyou-labs/aleo-vrf/issues/1). Terms (Beacon, Round, Consumer program, Randomness request, Relayer, Fulfillment, Delivery) are used as defined in [GLOSSARY.md](../GLOSSARY.md). The Leo 4 terms `fn` (off-chain, proved) and `final` (on-chain finalize) are used throughout.

Researched 2026-10-21.

## Verdict

| Path | Verdict | Basis |
|---|---|---|
| (a) BLS pairing check inside an off-chain `fn` (non-native BLS12-381 or BN254) | **Infeasible** | Measured. One emulated BLS12-381 Fp multiplication costs about 37,000 constraints in Leo. A whole deployment may hold 2^22 = 4,194,304 constraints, which is about 112 such multiplications. The squarings in a single Miller loop already need about 2,268. |
| (b) BLS pairing check in `final` | **Infeasible** | Read from source. There is no pairing or BLS12-381/BN254 opcode. A `final` block may spend at most 4,000,000 microcredits, and one emulated Fp multiplication compiles to about 880 instructions costing at least 440,000 microcredits. That allows about 9 Fp multiplications against a need of more than 10,000. |
| (c) Verify a succinct proof made elsewhere with `snark.verify` | **Plausible but unproven. Not recommended yet.** | The on-chain side is live and cheap (about 0.2 credits). The off-chain side is a Varuna/BLS12-377 circuit of roughly 20M+ constraints that nobody has built. It has to be written in Rust against snarkVM's circuit API, and its proving time and memory are unmeasured. |
| (d) Protocol or opcode support on testnet | **None, and no roadmap** | The snarkVM instruction set has no pairing op. The snarkVM, Leo and ARCs repos have no issue or ARC proposing one. |

**Conclusion.** No path has a measurement showing it works. Until one does, the service **cannot be called verifiable**, and per the parent map it must not be called a VRF. This defers to [#6 "Trusted-Relay Fallback or Stop"](https://github.com/mangekyou-labs/aleo-vrf/issues/6). Path (c) is the only open avenue. It is worth pursuing only as a separately scoped spike with the exit criteria listed under [Path (c)](#path-c-succinct-proof-verified-with-snarkverify).

**Chain choice** (the round-binding research hands this decision to this ticket). If any path is ever pursued, **evmnet** is the cheapest target:
- BN254 Fp needs 4 limbs, against 6 for BLS12-381.
- An emulated BN254 Fp multiplication measured about 2.1x cheaper.
- G1 has cofactor 1, so no subgroup check is needed on the signature.
- The digest uses Keccak-256, which Aleo has natively; SHA-256 does not exist as an opcode.

quicknet costs more because of BLS12-381 and SHA-256. The default chain is worst: it is chained, its signatures are on G2, it hashes to G2, and every check needs the previous signature.

## drand chain parameters

Live values come from `https://api.drand.sh/v2/beacons/<chain>/info`. Schemes come from [drand/drand `crypto/schemes.go` @ e8dd607](https://github.com/drand/drand/blob/e8dd607147c676086312b21c22d923dd6a07209a/crypto/schemes.go).

| Chain | Scheme ID | Period | Public key | Signature | Message digest | Hash-to-curve DST |
|---|---|---|---|---|---|---|
| quicknet (`52db9ba7...e971`) | `bls-unchained-g1-rfc9380` | 3 s | G2, 96 B compressed | G1, 48 B compressed | `SHA256(round_u64_be)` | `BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_` |
| evmnet (`04f1e906...c8c3`) | `bls-bn254-unchained-on-g1` | 3 s | BN254 G2, 128 B uncompressed | BN254 G1, 64 B uncompressed (x‖y, big-endian) | `Keccak256(round_u64_be)` | `BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_` |
| default (`8990e7a9...b2ce`) | `pedersen-bls-chained` | 30 s | G1, 48 B compressed | G2, 96 B compressed | `SHA256(prev_sig ‖ round_u64_be)` | `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_` |

For every scheme, randomness is `SHA256(signature)`. The scheme's verification equation is `e(sig, g2) == e(H(digest), pk)` on the G1-signature chains, and the mirror image on the default chain. Either way it is a **two-pairing product check, preceded by a hash-to-curve**. For evmnet, kyber v1.3.3 `pairing/bn254/point.go` hashes to G1 with `expand_message_xmd` over Keccak-256, two SVDW maps and a point addition.

Latest rounds sampled on 2026-10-21:
- quicknet 33,254,039, with a 48-byte signature
- evmnet 21,681,469, with a 64-byte signature
- default 6,571,148, with a 96-byte signature and a 96-byte previous signature

## Aleo limits (from source, not the local docs)

The source is [snarkVM @ 038b3ea](https://github.com/aleo-labs-protocol/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48) (ProvableHQ/snarkVM now redirects to aleo-labs-protocol/snarkVM). Testnet height was 20,684,129 on 2026-10-21, so testnet runs consensus V22 (V22 activated at 20,415,000 per `console/network/src/consensus_heights.rs`).

| Limit | Value at V22 | Source |
|---|---|---|
| Constraints and variables per deployment (all functions combined) | 2^22 = 4,194,304 (`MAX_DEPLOYMENT_CONSTRAINTS_V2`, from V19) | `console/network/src/lib.rs`, enforced in `synthesizer/process/src/stack/deploy.rs` |
| Deployment synthesis fee | 25 microcredits per constraint | `SYNTHESIS_FEE_MULTIPLIER`, `synthesizer/process/src/cost.rs` |
| Finalize spend per function | 4,000,000 microcredits (`TRANSACTION_SPEND_LIMIT`, from V10) | `console/network/src/lib.rs`, `cost.rs` |
| Finalize op cost | 500 for most integer and field ops; 10,000 for group/scalar mul; 100,000 + 50/byte for `snark.verify` | `synthesizer/process/src/cost.rs` |
| Instructions or commands per function | 65,535 | `MAX_INSTRUCTIONS` / `MAX_COMMANDS` |
| Program size | 2,048,000 B (from V16) | `MAX_PROGRAM_SIZE` |
| Transaction size | 2,304,000 B (from V16) | `MAX_TRANSACTION_SIZE` |
| Array elements | 2,048 | `MAX_ARRAY_ELEMENTS` |
| Inputs and outputs per function | 16 / 16 | `MAX_INPUTS` / `MAX_OUTPUTS` |
| Transitions per transaction | 32 | `TRANSACTION_DEPTH = 5`, `ledger/block/src/transaction/merkle.rs` |
| Functions or mappings per program | 31 / 128 (mappings 128 from V22) | `MAX_FUNCTIONS` / `MAX_MAPPINGS` |
| Universal SRS | powers of beta up to 2^28 | `parameters/src/mainnet/resources` |

The local docs are stale. `.claude/skills/aleo-docs/references/leo/language/programs_in_practice/limitations.md` still says 100 KB programs, 128 KB transactions and 100,000,000 microcredits. The installed Leo 3.4.0 also still enforces the 100,000-byte program cap at build time, which is why the measurements below are split into several programs.

## Measurements

The prototype lives in [`research/drand-verification-prototype/`](drand-verification-prototype/). `gen.py` generates straight-line Leo for each building block (`python3 -I gen.py <fp381|fp254|sha256_16|sha256_32|natives> > drand_<name>/src/main.leo`). Each block was then synthesized with `leo synthesize drand_<name>.aleo --local --network testnet`, using Leo 3.4.0 on an Apple M4 (10 cores, 16 GB).

The Fp multiplication is a textbook Montgomery CIOS over u64 limbs with u128 intermediates and a final conditional subtraction. I checked its output against Python: `[1..6] * [7..12]` gives the correct Montgomery product. Each "marginal" figure subtracts an I/O baseline transition that has the same input and output shapes but does no arithmetic.

| Transition | Constraints | Baseline | Marginal |
|---|---|---|---|
| `fp381_mul` (BLS12-381 Fp, 6 limbs) | 51,620 | 14,433 | **37,187** |
| `fp254_mul` (BN254 Fp, 4 limbs) | 31,691 | 14,162 | **17,529** |
| `sha256_16_rounds` | 24,187 | 14,443 | 9,744 |
| `sha256_32_rounds` | 37,099 | 14,443 | 22,656 |
| SHA-256 compression, 64 rounds (extrapolated: 9,744 + 3 x 12,912) | | | **~48,500** (estimate) |
| `keccak_round` (native `Keccak256::hash_to_bits_raw(u64)`) | 164,246 | ~14,200 (estimate) | **~150,000** |
| `native_field_mul` (reference) | 15,172 | | a native mul is about 1 constraint |

What the measurements show:
- An emulated BLS12-381 Fp multiplication in Leo costs about **37,000x** a native field multiplication.
- gnark does the same job with range-check and log-derivative lookup gadgets, which Leo lacks. Its full emulated BLS12-381 pairing costs 1,322,686 R1CS on BN254 Groth16 (`internal/stats/latest_stats.csv` @ [Consensys/gnark ce93ba9](https://github.com/Consensys/gnark/blob/ce93ba94b216ce5ef7394418d7d4c5569ffe5684/internal/stats/latest_stats.csv)). That is about 36 Leo Fp multiplications.
- The `fp381_mul` program compiles to about 880 Aleo instructions.

Proving time was also measured, very roughly. Wall clock of `leo execute` against the testnet API includes the fee proof and network fetches. It was 7 s for the I/O baseline, 10 s for `fp381_mul` and 14 s for `keccak_round`. That implies a marginal proving rate on the order of 10,000-50,000 constraints per second on this laptop. **This rate is an estimate, not a benchmark.**

## Path (a): pairing check inside an off-chain `fn`

The pairing cost below is my estimate, not a measurement.
- The BLS12-381 Miller loop parameter |x| = 0xd201000000010000 has 64 bits and Hamming weight 6. One Miller loop therefore needs 63 Fp12 squarings, about 36 Fp multiplications each.
- That gives a hard lower bound of **2,268 Fp multiplications for the squarings of one Miller loop alone**, before line evaluations, point arithmetic, the second Miller loop or the final exponentiation.
- A realistic count for a two-pairing check with shared final exponentiation is about 18,000 Fp-multiplication equivalents. Hash-to-curve and subgroup checks come on top of that.

| | BLS12-381 (quicknet, default) | BN254 (evmnet) |
|---|---|---|
| Fp multiplications per whole deployment (2^22 / marginal) | ~112 | ~239 |
| Lower bound: squarings of one Miller loop | 2,268 x 37,187 ≈ 84M (20x the limit) | ~64 x 36 x 17,529 ≈ 40M (9.6x the limit) |
| Rough full check at ~18,000 Fp mul | ≈ 670M constraints (≥ 160 maximal deployments) | ≈ 315M constraints (≥ 75 maximal deployments) |
| Message hashing | ~12 SHA-256 compressions (`expand_message_xmd` plus the digest) ≈ 0.6M | ~6 Keccak calls ≈ 0.9M |
| Rough proving time at 10k-50k constraints/s | ~4-19 hours per Round | ~2-9 hours per Round |

Even if the check were split across chained transitions, it would need hundreds of separately deployed programs (each deployment is capped at 2^22 combined), multiple 32-transition transactions per Round with the intermediate Fp12 state carried between them, and hours of proving per Round. drand emits a Round every 3 s. **Path (a) is infeasible.** Leo-level gadgets would also need witness hints (for example inverses supplied as private inputs and checked), which helps by constant factors only, not by the 20x needed.

## Path (b): pairing check in `final`

- `synthesizer/program/src/logic/instruction/mod.rs` has no pairing, BLS12-381 or BN254 instruction, and no SHA-256 instruction.
- `final` has no runtime loops (Leo unrolls them), so instruction count is bounded by `MAX_COMMANDS` = 65,535.
- Cost: about 880 instructions x 500 microcredits ≥ 440,000 microcredits per emulated Fp multiplication. The 4,000,000 per-function cap allows about 9.
- A pairing check would cost on the order of 10^10 microcredits and about 10^7 commands.

**Path (b) is infeasible by 3 to 4 orders of magnitude.**

## Path (c): succinct proof verified with `snark.verify`

On-chain side (read from source, works today):
- `snark.verify` / `snark.verify.batch` (Leo `Snark::verify`) are allowed only in `final` and are available from V14. Varuna V3 is required from V21. Source: `synthesizer/program/src/logic/instruction/operation/snark_verify.rs`, added in snarkVM PR #3004.
- The verifying key and proof are arbitrary byte arrays, deserialized as snarkVM `VerifyingKey<N>` / `Proof<N>`. Any Varuna circuit over BLS12-377 that uses the Aleo universal SRS is accepted. The circuit does not have to be a deployed Aleo function, so **the 2^22 deployment limit does not apply**. The SRS goes up to 2^28.
- snarkVM's own test (`synthesizer/src/vm/tests/test_v14/snark_verify.rs`) uses a 673-byte verifying key and a 957-byte proof, both well inside 2,048-element arrays.
- Cost: about 100,000 + 50 x (673 + 957 + inputs) ≈ 0.2 credits, far below the 4,000,000-microcredit cap.
- A Groth16 or PLONK proof from gnark, circom or SP1 **cannot** be verified, because the only verifier is Varuna on BLS12-377.

Off-chain side (unbuilt and unmeasured):
- snarkVM's `circuit/` crate has no non-native field gadget. It provides BHP, Pedersen, Poseidon, Keccak and Elligator2 only.
- The Relayer would need a new Rust circuit, written against snarkVM's circuit environment, that does emulated Fp, Fp2, Fp6 and Fp12 arithmetic, the Miller loop, the final exponentiation, hash-to-curve and on-curve/subgroup checks.
- The best reference for plain R1CS without lookups is [yi-sun/circom-pairing @ 107c316](https://github.com/yi-sun/circom-pairing/blob/107c316223a08ac577522c54edd81f0fc4c03130/README.md). Its BLS12-381 signature `verify` is **19.2M constraints**, excluding SHA-256. Groth16 proving with rapidsnark took 2 min on a 32-core, 256 GB machine with a 12 GB proving key.
- Varuna is a different prover with more polynomial work, so a comparable circuit would need a domain of about 2^25 and very likely tens of GB of RAM and minutes per proof. **That is an estimate.**

Path (c) is the only one not ruled out. Nothing measured shows it working, so it is **not recommended** here. It could be revived as its own spike with these exit criteria:
1. A snarkVM Rust gadget for one BLS12-381 or BN254 Fp multiplication with a measured constraint count. The target is low thousands of constraints.
2. A full evmnet verification circuit with measured constraints, Varuna proving time and peak memory on Relayer hardware.
3. A testnet `final` that calls `snark.verify` on a real Round.

## Path (d): protocol or opcode support

- The instruction enum at snarkVM 038b3ea contains no pairing operation. The only BLS12-381/BN254 references are a CUDA build feature in `algorithms/cuda`.
- GitHub searches for pairing, BLS12-381, BN254, drand, SHA-256 and randomness in aleo-labs-protocol/snarkVM, /leo and /ARCs found no open or closed proposal.
- The only related open work is snarkVM PR #3470, "Reduce hashing in the varuna verifier", which affects path (c) cost only.
- **Nothing to wait for.**

## Encoding (applies only if path (c) is pursued)

- **Public key.** Pin it in the Consumer-facing program: either as a constant, or as a constant hash of the `snark.verify` public inputs that commit to it. It must never come from the Relayer. Use evmnet's 128-byte uncompressed G2 key, or a field-hash of it, as a circuit constant. Then the verifying key alone binds the Beacon.
- **Verifying key.** The `snark.verify` VK is a caller-supplied byte array. `final` must compare it, or a hash of it, to a pinned constant. Without that check, anyone can supply their own circuit.
- **Round.** A public input (u64 fits in one field element). The circuit recomputes the digest from it. `final` checks that it equals the Round recorded in the Randomness request.
- **Signature or randomness.** The 64-byte evmnet signature does not fit in one 253-bit field element. Expose the 32-byte randomness `SHA256(sig)` as two 128-bit field inputs and keep the signature private to the circuit. SHA-256 must then be computed in-circuit as well; that cost is included above.

## Security notes

- **Malformed points.** The circuit must check that each coordinate is below p (a canonical encoding) and that every point is on the curve. BLS12-381 G1/G2 and BN254 G2 also need subgroup checks. circom-pairing measured about 0.8M constraints each for the BLS12-381 checks. BN254 G1 has cofactor 1, so evmnet signatures need only the on-curve check. The public key is a pinned constant, so its checks can be done once offline.
- **Replayed or mismatched Rounds.** Bind the Round inside the proof (it is hashed into the digest) and expose it as a public input. In `final`, assert it equals the Round stored for the Randomness request. Record Fulfillment in a mapping keyed by request so a second Delivery aborts.
- **Chained scheme.** The default chain's digest depends on `previous_signature`, which adds 96 bytes of input and a second signature that is not itself checked. Avoid it.
- **Unproven construction.** Until path (c) is built and measured, any Delivery is trusted-Relayer data. It must not be described as verifiable or as a VRF ([#6](https://github.com/mangekyou-labs/aleo-vrf/issues/6)).

## Caveats

- Measurements used Leo 3.4.0. Current Leo (aleo-labs-protocol/leo @ 424e1ad) uses Leo 4 syntax and a newer snarkVM. The integer gadgets that dominate the cost are the same kind, but the counts may shift somewhat.
- The pairing operation counts and proving rates are estimates, labelled as such above. The infeasibility of (a) rests on a lower bound 20x over the limit, so it does not depend on those estimates being precise.

## Sources

- snarkVM [aleo-labs-protocol/snarkVM @ 038b3ea](https://github.com/aleo-labs-protocol/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48): `console/network/src/lib.rs`, `console/network/src/consensus_heights.rs`, `synthesizer/process/src/cost.rs`, `synthesizer/process/src/stack/deploy.rs`, `synthesizer/program/src/logic/instruction/mod.rs`, `synthesizer/program/src/logic/instruction/operation/snark_verify.rs`, `synthesizer/src/vm/tests/test_v14/snark_verify.rs`, `circuit/algorithms/src`, `console/program/src/state_path/configuration/mod.rs`
- Leo [aleo-labs-protocol/leo @ 424e1ad](https://github.com/aleo-labs-protocol/leo/tree/424e1ad1ca3f031538ee400252bc103196e81f3d); local docs `.claude/skills/aleo-docs/references/leo/language/operators/cryptographic_operators.md`
- drand [drand/drand @ e8dd607](https://github.com/drand/drand/tree/e8dd607147c676086312b21c22d923dd6a07209a) `crypto/schemes.go`; kyber v1.3.3 `pairing/bn254/point.go`; `https://api.drand.sh/v2/beacons/{quicknet,evmnet,default}/info`
- gnark [Consensys/gnark @ ce93ba9](https://github.com/Consensys/gnark/tree/ce93ba94b216ce5ef7394418d7d4c5569ffe5684) `internal/stats/latest_stats.csv`, `internal/stats/snippet.go`
- circom-pairing [yi-sun/circom-pairing @ 107c316](https://github.com/yi-sun/circom-pairing/tree/107c316223a08ac577522c54edd81f0fc4c03130) README benchmarks
- Testnet height: `https://api.explorer.provable.com/v2/testnet/block/height/latest`
