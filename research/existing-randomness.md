# Existing Randomness on Aleo

Research for [#2 Existing Randomness on Aleo](https://github.com/mangekyou-labs/aleo-vrf/issues/2) (parent map [#1](https://github.com/mangekyou-labs/aleo-vrf/issues/1)). Terms follow [GLOSSARY.md](../GLOSSARY.md) and Leo 4 syntax (`fn`, `final { }`, `Final`).

Date: 2026-10-21. Code citations are pinned to snarkVM `staging` at commit [`038b3ea`](https://github.com/aleo-labs-protocol/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48) (2026-10-20). The ProvableHQ repos (`snarkVM`, `leo`, `snarkOS`, `ARCs`) now redirect to `aleo-labs-protocol/*`.

## Answer

- **Today an Aleo program has exactly one source of on-chain randomness: the native `ChaCha::rand_*` (the `rand.chacha` opcode).** It works only inside `final { }` or a `final fn`. Its seed comes from public block data plus transaction-specific values. Every validator can compute the output, and the block producer can bias it by grinding a limited number of choices. It has no external entropy and produces no proof of unbiasability.
- **No drand-backed randomness service is live on Aleo mainnet or testnet.** I found no program, relay, ARC or snarkVM issue that brings drand rounds on-chain. Searches turned up only two voting apps that use drand timelock encryption off-chain. Neither one is a Beacon. **The destination does not need redrawing.**
- **The only other randomness on offer is off-chain:** the Aleo Oracle's TEE-attested `/random` endpoint. On-chain programs check an SGX or Nitro enclave signature. The requester sees the value before submitting it, so they can re-roll, and the value is not bound to a future Round.
- **snarkVM has no pairing opcode and no BLS12-381 support, and nothing on the roadmap proposes one.** Signature-check opcodes exist for Aleo Schnorr (`sign.verify`) and ECDSA/secp256k1 (V11). Since V14 there is also `snark.verify` for Varuna proofs over BLS12-377. That opcode matters for the drand-verification ticket.

## 1. Native `ChaCha::rand_*` in `final`

### Surface

Leo exposes `ChaCha::rand_<type>()` for `address`, `bool`, `field`, `group`, `i8`..`i128`, `u8`..`u128` and `scalar`. The docs say "This operation can only be used inside a `final { }` block or inside a `final fn`" ([Leo docs, cryptographic_operators.md:1401-1426](../.claude/skills/aleo-docs/references/leo/language/operators/cryptographic_operators.md)). The opcode underneath, `rand.chacha`, takes up to `MAX_ADDITIONAL_SEEDS = 2` extra operands that the program supplies ([rand_chacha.rs:26, 81](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/command/rand_chacha.rs#L26)). Leo has no view-level variant. The opcode needs a `transition_id` and a `nonce`, and view execution supplies neither, so it fails there ([rand_chacha.rs:92-112](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/command/rand_chacha.rs#L92-L112)).

### How the value is derived

1. **Block seed.** `FinalizeGlobalState::new` sets `random_seed = BHP768(block_round, block_height, block_cumulative_weight, block_cumulative_proof_target, previous_block_hash [, block_timestamp])`, truncated to 32 bytes ([finalize_global_state/mod.rs:59-90](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/finalize_global_state/mod.rs#L59-L90)). The VM fills in these fields from the block being added. The timestamp is included only from consensus V12 on ([vm/mod.rs:498-520](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/src/vm/mod.rs#L498-L520); same in speculation, [vm/finalize.rs:305-325](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/src/vm/finalize.rs#L305-L325)). The block timestamp is the stake-weighted median of certificate timestamps in the committed subdag ([narwhal/subdag/src/lib.rs:331-344](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/ledger/narwhal/subdag/src/lib.rs#L331-L344)).
2. **Per-call preimage.** From V3 on, `rand.chacha` hashes `random_seed || transition_id || program_id || function_name || nonce || destination locator || destination type || extra operands` with BHP1024. It then seeds `ChaCha20Rng::from_seed` with the 32-byte digest and samples the destination type ([rand_chacha.rs:89-135](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/command/rand_chacha.rs#L89-L135)). Before V3 the preimage had no nonce.
3. **Nonce.** The nonce is a counter, not entropy. It starts at 0 for each top-level transition and goes up by one for each awaited sub-transition ([process/src/finalize.rs:517-626](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/process/src/finalize.rs#L517-L626)). Constructors always use nonce 0 ([finalize.rs:414-416](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/process/src/finalize.rs#L414-L416)).

### Who supplies the entropy

No one supplies entropy in the usual sense. The only inputs the requester cannot control are the five or six block fields, and the Narwhal/Bullshark committee produces those as a side effect of consensus. No VRF, threshold signature or external Beacon goes into the seed. The finalization context is public by design: "All inputs and operations are publicly visible" ([Leo docs, guides/01_finalization.md:14](../.claude/skills/aleo-docs/references/leo/guides/01_finalization.md)).

### Can validators or proposers predict or bias it?

My analysis, based on the code above:

- **Predict: yes.** Once the subdag for a block commits, every input is public and fixed, so every validator, and anyone following the DAG, can compute every `rand.chacha` output before finalization runs. The output is unpredictable only until the block's contents are settled. Nobody holds it as a secret.
- **Bias: yes, by limited grinding.** The leader whose anchor certificate commits the subdag, and validators more broadly, influence the seed in several ways:
  - which certificates and solutions go into the block, which changes `cumulative_weight`, `cumulative_proof_target` and the median timestamp;
  - whether a given transaction lands in this block or a later one (delay or censorship);
  - whether an anchor is withheld, which changes `block_round`.
  Each choice re-rolls the output. A leader can simulate the alternatives and pick a favorable one, constrained by liveness and the anchor timing rules.
- **Proof:** a consumer gets no on-chain artifact showing that the value was not ground.

### Can the requester observe it before committing?

- **Not before broadcast.** `random_seed` depends on the block that eventually includes the transaction. The requester learns the output only when that block is produced.
- **But a program can see the outcome inside the same transaction and abort.** Final blocks are atomic and revert on failure ([functions.md:49](../.claude/skills/aleo-docs/references/leo/language/programs_in_practice/functions.md)), and programs can read other programs' mappings, e.g. `credits.aleo::account.get(addr)` ([public_storage.md:43](../.claude/skills/aleo-docs/references/leo/language/programs_in_practice/public_storage.md)). A wrapper program can call a Consumer program, await its `Final`, read the outcome from the Consumer's mappings, and `assert` on it. An unfavorable draw then reverts the whole transaction, and the attacker pays only the fee. A Consumer program that uses `ChaCha::rand_*` has to defend against this itself, for example by rejecting non-signer callers or splitting commit and reveal across transactions.

### Status and history

- Introduced in snarkVM [PR #1670](https://github.com/ProvableHQ/snarkVM/pull/1670) (merged 2023-06-14). That PR also added `cumulative_proof_target` to block metadata.
- Transition-ID selection in finalize was fixed in [PR #2596](https://github.com/ProvableHQ/snarkVM/pull/2596).
- Cost re-priced in [PR #3356](https://github.com/ProvableHQ/snarkVM/pull/3356) (merged 2026-10-05). The change activates at V22: "Modifies the cost of the rand.chacha opcode to a more accurate value" ([consensus_heights.rs:84-87](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/console/network/src/consensus_heights.rs#L84-L87)). V22 heights are 22,962,000 on mainnet and 20,415,000 on testnet ([consensus_heights.rs:194, 221](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/console/network/src/consensus_heights.rs#L194)). Both networks were past those heights on 2026-10-21, at about 23.00M and 20.68M.
- Leo [PR #29491](https://github.com/ProvableHQ/leo/pull/29491) (2026-06-05) stops dead-code elimination from removing unused ChaCha draws. A draw affects the results of later draws through the destination locator, so removing one would change them.
- Live on mainnet and testnet. This is the production randomness primitive.

## 2. Opcodes relevant to verifying an external Beacon

The snarkVM operation set contains `assert`, `async`, `call` (static and dynamic), `cast`, `commit`, `deserialize`, `ecdsa_verify`, `get_record_dynamic`, `hash` (BHP, Pedersen, Poseidon, Keccak, SHA3), `is`, `serialize`, `sign_verify` and `snark_verify` ([operation/](https://github.com/aleo-labs-protocol/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/instruction/operation)).

- **`snark.verify` / `snark.verify.batch`** (V14) verify Varuna proofs on BLS12-377, with up to 32 circuits and 128 instances ([consensus_heights.rs:56-60](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/console/network/src/consensus_heights.rs#L56-L60), [snark_verify.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/instruction/operation/snark_verify.rs)). The V14 heights are 17,700,000 on mainnet and 15,370,000 on testnet.
- **ECDSA verify** (V11) and Aleo Schnorr `sign.verify`.
- **No pairing opcode and no BLS12-381 curve.** The curves crate has only `bls12_377` and `edwards_bls12` ([curves/src](https://github.com/aleo-labs-protocol/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48/curves/src)), and `bls12_381` appears nowhere in the tree. drand mainnet and quicknet signatures are BLS on BLS12-381 ([drand cryptography](https://docs.drand.love/docs/cryptography/), [drand specification](https://docs.drand.love/docs/specification/)), so a program cannot check them directly today.

## 3. Survey

| Candidate | What it is | Trust model | Status |
|---|---|---|---|
| Native `ChaCha::rand_*` | Block-seeded ChaCha20 in `final` (section 1) | Trust the validator set not to grind; the result is visible to all validators before finalization; exposed to wrapper-abort | **Live** on mainnet and testnet |
| drand-backed Beacon / Relayer | drand Rounds delivered on-chain | n/a | **None found.** GitHub repo and code searches for "aleo drand" find only this repo. Web search finds nothing |
| drand tlock in voting apps | [storswiftlabs/powervoting](https://github.com/storswiftlabs/powervoting), [deeranex/privote](https://github.com/deeranex/privote): Leo comments describe encrypting votes off-chain with drand timelock | drand (off-chain only) | Not a randomness service; nothing verified on-chain |
| Aleo Oracle "attested random" ([venture23-aleo](https://github.com/venture23-aleo), formerly zkPortal) | The notarization backend's `GET /random?max=N` returns an SGX-attested `crypto/rand` number ([api-documentation.md](https://github.com/venture23-aleo/aleo-oracle-notarization-backend/blob/HEAD/docs/api-documentation.md)); SDK `getAttestedRandom` ([aleo-oracle-docs sdk](https://github.com/zkportal/aleo-oracle-docs/blob/HEAD/docs/sdk/index.md)) | Trust Intel SGX / AWS Nitro, the enclave code and the operator. **The requester fetches the value off-chain, sees it, and can re-roll before submitting**; the value is not bound to a future Round | Backend live; on-chain verification via `official_oracle.aleo` |
| `official_oracle.aleo` | On-chain verifier for enclave reports (`set_data_sgx`, `set_data_nitro`, mappings `sgx_attested_data`, `nitro_attested_data`, `allowed_keys`, `sgx_unique_id`, `nitro_pcr_values`); contracts and Veridise audit in [aleo-oracle-contracts](https://github.com/venture23-aleo/aleo-oracle-contracts) | `sign.verify` against admin-set allowed keys and enclave measurements; admin key trusted | **Deployed** on mainnet and testnet ([mainnet](https://api.explorer.provable.com/v1/mainnet/program/official_oracle.aleo), [testnet](https://api.explorer.provable.com/v1/testnet/program/official_oracle.aleo)); testnet also has `veru_oracle_interface_v5.aleo` |
| Eclipse oracle | [EclipseAleo/oracle-sdk](https://github.com/EclipseAleo/oracle-sdk): `getFeedFullData`, `getCurrentPrice` | Feed operators | Price feeds only, no randomness |
| Other-chain VRFs (ORAO, Chainlink, Switchboard, Pyth Entropy) | | | None targets Aleo (e.g. [ORAO VRF](https://github.com/orao-network) covers Solana and Fuel) |
| snarkVM / ARC roadmap: pairing, BLS12-381, VRF, drand | | | **Nothing found.** Issue/PR searches over aleo-labs-protocol/{snarkVM, leo, snarkOS, ARCs} and AleoNet for `drand`, `bls12-381`, `pairing`, `VRF`, `BLS signature`, `bn254` turn up only unrelated or internal (Varuna/KZG) items, e.g. [snarkVM #2952](https://github.com/ProvableHQ/snarkVM/issues/2952). The open ARC PRs ([list](https://github.com/aleo-labs-protocol/ARCs/pulls)) cover token standards, governance, exchange addresses and flagged ops. Leo [#958 "Randomness in Leo core"](https://github.com/ProvableHQ/leo/issues/958) is closed and was satisfied by ChaCha |

## 4. Scope check for the map

**No live drand-backed service exists, so the destination stands.** The niche is still open: nothing on Aleo delivers a randomness value that is bound to a future Round, that neither validators nor the requester can choose, and whose correctness a Consumer program can check against a public Beacon.

## 5. Implications for other tickets

- **drand verification feasibility:** with no pairing or BLS12-381 opcode, a direct on-chain BLS check is out. The candidates are (a) a Varuna proof, checked with `snark.verify`, that a BLS12-381 signature verifies, which would require emulating non-native BLS12-381 arithmetic inside a BLS12-377 circuit and is expected to be expensive, or (b) a trusted or committee Relayer. That ticket should size (a).
- **Consumer program design:** whatever the Delivery mechanism, the wrapper-abort pattern from section 1 applies to any Fulfillment that a Consumer program reads in the same transaction. Commit to the Randomness request (and its Round) in one transaction and settle in a later one.
- **Baseline to beat:** `ChaCha::rand_*` is free and synchronous. A drand-based design is worth it only if it removes validator predictability and grinding and makes the bias resistance checkable. The design should say so explicitly.

## Sources

- snarkVM @ `038b3ea`: [rand_chacha.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/command/rand_chacha.rs), [finalize_global_state/mod.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/finalize_global_state/mod.rs), [vm/mod.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/src/vm/mod.rs), [vm/finalize.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/src/vm/finalize.rs), [process/src/finalize.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/process/src/finalize.rs), [narwhal/subdag/src/lib.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/ledger/narwhal/subdag/src/lib.rs), [consensus_heights.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/console/network/src/consensus_heights.rs), [snark_verify.rs](https://github.com/aleo-labs-protocol/snarkVM/blob/038b3ead6660e4db56a727f76d3f75f325dcda48/synthesizer/program/src/logic/instruction/operation/snark_verify.rs)
- Leo docs (local mirror): `.claude/skills/aleo-docs/references/leo/language/operators/cryptographic_operators.md`, `language/programs_in_practice/functions.md`, `language/programs_in_practice/public_storage.md`, `guides/01_finalization.md`
- snarkVM PRs #1670, #2596, #3356; Leo PR #29491, issue #958
- Aleo Oracle: venture23-aleo/aleo-oracle-notarization-backend, venture23-aleo/aleo-oracle-contracts, zkportal/aleo-oracle-docs; explorer API for `official_oracle.aleo`
- drand: [specification](https://docs.drand.love/docs/specification/), [security model](https://docs.drand.love/docs/security-model/), [cryptography](https://docs.drand.love/docs/cryptography/)
