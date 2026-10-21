# Round Binding Rule

Research for [#4 Round Binding Rule](https://github.com/mangekyou-labs/aleo-vrf/issues/4) (map: [#1](https://github.com/mangekyou-labs/aleo-vrf/issues/1)). Terms follow [`GLOSSARY.md`](../GLOSSARY.md).

Source pins used below:
- snarkVM `staging` @ [`038b3ea`](https://github.com/ProvableHQ/snarkVM/tree/038b3ead6660e4db56a727f76d3f75f325dcda48)
- snarkOS `staging` @ [`508b001`](https://github.com/ProvableHQ/snarkOS/tree/508b0013af57e4d51077102409721b13845545d4)
- drand `master`, [`common/time.go`](https://github.com/drand/drand/blob/master/common/time.go) and [`internal/chain/beacon/node.go`](https://github.com/drand/drand/blob/master/internal/chain/beacon/node.go)
- Leo docs (vendored): `.claude/skills/aleo-docs/references/leo/language/operators/standard_operators.md`

## Proposed rule (summary)

1. **The program derives the target round itself, in `final`, from `block.timestamp`.** The request function takes no round argument. The request records `target_round` in a mapping. A caller-chosen round with a minimum-lead check is rejected as a design (see "Derive vs. accept").
2. `target_round` is the smallest round `r` with `G + (r - 1) * P >= block.timestamp + MIN_LEAD`, where `MIN_LEAD = 30 s`. In integer form: `target_round = (block.timestamp + MIN_LEAD - G + P - 1) / P + 1`.
3. **Fulfillment** has to supply exactly the stored `target_round`, plus a beacon signature for it that passes verification. Any other round is rejected. Fulfillment is permissionless: anyone may submit it, not just the relayer or the requester. Each request can be fulfilled once.
4. **Output**: `out = Hash(DOMAIN_V1, chain_hash_id, request_id, consumer, consumer_tag, target_round, beacon_signature)`. `request_id` comes from an on-chain counter. `consumer` is `self.caller`, the address of the consumer program, which is passed into `final`.
5. **Timeout**: an unfulfilled request becomes eligible for timeout once `block.timestamp >= round_time(target_round) + TIMEOUT_GRACE`, where `TIMEOUT_GRACE = 3600 s`. Fulfillment stays valid until a timeout has actually been executed. The first of the two to finalize wins.

## Beacon (drand) chain parameters

These come from the live `/info` endpoints at `https://api.drand.sh/<chainhash>/info` and `https://api.drand.sh/v2/beacons/<id>/info`, fetched on 2026-10-21:

| Beacon ID | Chain hash | `genesis_time` (G) | `period` (P) | Scheme |
|---|---|---|---|---|
| `quicknet` | `52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971` | 1692803367 | 3 s | `bls-unchained-g1-rfc9380` (BLS12-381, sig on G1) |
| `evmnet` | `04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3` | 1727521075 | 3 s | `bls-bn254-unchained-on-g1` (BN254) |
| `default` | `8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce` | 1595431050 | 30 s | `pedersen-bls-chained` (BLS12-381, chained) |

Round timing comes from drand `common/time.go`. `TimeOfRound(P, G, r) = G + (r - 1) * P`, so round 1 is at genesis. `CurrentRound(now) = floor((now - G) / P) + 1`. I checked this against live `/rounds/latest` at unix 1792560346. quicknet reported 33252327 and evmnet reported 21679758, which matches the formula exactly.

Clock behaviour that matters for publication time:
- Each drand node starts signing round `r` when its own wall clock reaches `TimeOfRound(r)`. It uses a `clockwork` ticker on system time, per `internal/chain/beacon/ticker.go`.
- `ProcessPartialBeacon` accepts partials up to one round in the future ("we allow one round off in the future because of small clock drifts") and rejects partials further ahead. `internal/chain/beacon/node.go`, lines ~137-147.
- **Assumption D1:** fewer than a threshold of drand nodes are malicious, and honest drand clocks are within about 1 s of UTC (NTP). Under D1, round `r` cannot exist before `TimeOfRound(r) - P`. I budget a full period `P` of early publication as worst-case slack.
- Late rounds still get produced. After an outage, drand nodes catch up and sign the missed rounds (there is a `CatchupPeriod` group parameter), so a round that is late will normally be published eventually. A round that is *never* published requires a permanent halt of the beacon.

The program must pin **one** chain hash and its `(G, P)` as constants. The choice of chain belongs to the verification-feasibility ticket. Aleo has no BLS12-381 or BN254 pairing operator and no SHA-256 operator in the Leo docs (`cryptographic_operators.md` lists BHP, Pedersen, Poseidon, Keccak, SHA3 and ECDSA only), so how a round gets verified is still open.

## What Aleo `final` exposes

- `block.height: u32` and `block.timestamp: i64` can only be used inside `final { }` or a `final fn`. Using them anywhere else is a compile error (Leo `standard_operators.md` §`block.height`, §`block.timestamp`; cheatsheet lines 491-492).
- The docs describe these as the "latest block". In snarkVM, the finalize state is built from **the block that contains the transaction**: `FinalizeGlobalState::new(block.round(), block.height(), block_timestamp, ...)` in `synthesizer/src/vm/finalize.rs` (~L307-325), and with `next_height` / `next_timestamp` when a block is being produced in `ledger/src/advance.rs` (~L414-431). So `block.timestamp` is the timestamp of the block that finalizes the request. When the proof was generated, or how long the transaction sat in the mempool, has no effect on it.
- `block_timestamp` is `Some` only from `ConsensusVersion::V12` onward (`finalize.rs` L307). Current testnet is past that point.
- `self.caller` (the immediate caller, i.e. the consumer program's address when it is called cross-program) is available in the proof context and gets passed into `final` as an argument (`standard_operators.md` §`self.caller`).

## How Aleo block timestamps are produced and validated

Production:
- A quorum block's timestamp is the **stake-weighted median of the certificate timestamps in round `anchor_round - 1`** of the committed subdag. See `Subdag::timestamp` and `weighted_median` in `ledger/narwhal/subdag/src/lib.rs` (L111-138, L331-344).
- Each certificate timestamp is the author's `now()` at proposal time (snarkOS `node/bft/src/primary.rs` ~L806-826).

Validation:
- **Future bound (BFT):** every batch header and certificate must satisfy `timestamp <= now() + MAX_TIMESTAMP_DELTA`, where `MAX_TIMESTAMP_DELTA = 10 s`. See `check_timestamp_for_liveness` in `node/bft/src/helpers/timestamp.rs`, the constant in `node/bft/src/lib.rs` L79, and the call sites in `node/bft/src/helpers/storage.rs` L563-564 and L722-723.
- **Per-author spacing:** a peer's certificate timestamp must be at least `MIN_BATCH_DELAY = 1 s` after that author's previous-round certificate, and must not be before it (`check_peer_proposal_timestamp`, `primary.rs` L1743-1762). The spacing is only checked when the previous certificate is known locally.
- **Block header:** `timestamp == expected_timestamp`, meaning the recomputed subdag median, and `timestamp <= current_timestamp`, the verifying node's wall clock. See `ledger/block/src/header/metadata/verify.rs` L74-80, plus `ledger/block/src/verify.rs` L247-253. `check_validity` only requires `timestamp > GENESIS_TIMESTAMP`.
- **No explicit monotonicity check** on `block.timestamp` compared with the previous block. `verify.rs` L421 uses `timestamp.saturating_sub(previous_block.timestamp())`, which tolerates a non-increasing value. In practice the median of strictly advancing per-author timestamps advances, but **the program must not rely on strict monotonicity**.

How far validators can influence it:
- **Assumption A1:** Byzantine stake is below 1/3 (the AleoBFT assumption), and honest validator clocks are within about 2 s of UTC. The median is then pinned to honest timestamps, except in the edge case where honest stake in the included certificates is exactly half. Where that edge case holds, it is still capped at `now + 10 s` going forward.
- A **future** skew (up to +10 s) is harmless for binding, because it only pushes the target further out. A **past** skew is the dangerous direction, because it would make an already-published round look like a future one. Under A1 it is limited to honest clock lag.

Block time and finality:
- AleoBFT (Narwhal DAG plus Bullshark-style commits) commits a leader certificate of an even round once the availability threshold (f+1 stake) of next-round certificates reference it (`node/bft/src/bft.rs` L312-374). A committed block is final, with no probabilistic reorg window.
- Round pacing comes from `MIN_BATCH_DELAY = 1 s`, `MAX_BATCH_DELAY = 2.5 s`, and `MAX_LEADER_CERTIFICATE_DELAY = 5 s` (`lib.rs` L57-74).
- Latency from `block.timestamp` (round `anchor-1`) to commit (round `anchor+1` reaches availability) is about 2-3 BFT rounds, roughly 3-8 s in normal operation. If a leader fails, the anchor is skipped. Its transactions then commit under a later anchor with a **later** `block.timestamp`, so a skip moves the target round forward rather than backward.
- I measured testnet on 2026-10-21. 10,000 blocks took 26,462 s (2.65 s/block) and 100,000 blocks took 269,037 s (2.69 s/block). Over the last 50 blocks the gaps ranged from 2 to 12 s, with a mean of 2.98 s. The latest block's timestamp was about 5 s behind my local clock at query time.
- Because the gaps vary, converting `block.height` to wall time drifts without bound. That is why the rule uses `block.timestamp`, not height.

## Derive vs. accept

**Derive (chosen).** `target_round` is a pure function of `block.timestamp` of the request's finalizing block and pinned constants. This has four consequences:
- Neither the caller nor the relayer can name a round, so "substitute a different round" cannot even be expressed.
- Mempool delay cannot shift the target into the past, because it is computed at finalization.
- Requests made within the same `P`-second window share a round. Batching comes for free, and one beacon signature fulfills them all.
- The only lever left is validator influence over `block.timestamp`, which A1 bounds.

**Accept with a min-lead check (rejected).** This option would let the caller pick any round `>= derived_min`. It does not leak outputs, but it adds surface for no benefit:
- The caller could spread requests across chosen rounds.
- Integrations get room to pass a stale or mismatched round.
- Callers need an extra off-chain clock estimate.

## Safety margin

The requirement is that the target round cannot be published before the request is final. Writing `T` for the request block's `block.timestamp`:

```
round_time(target) >= T + MIN_LEAD
need: MIN_LEAD > commit_latency + aleo_clock_lag + drand_early
               ≈ 8 s          + 2 s            + P (3 s quicknet/evmnet, 30 s default)
```

- `commit_latency` (≤ about 8 s, normal operation): the time from round `anchor-1` to commit.
- A Byzantine leader that withholds its anchor after seeing the output has to decide by round `anchor`, about 2.5-5 s after `T`. That is well inside `MIN_LEAD`, so it cannot grind.
- `aleo_clock_lag` (≤ 2 s): assumption A1.
- `drand_early` (≤ P): assumption D1, plus the one-round partial-acceptance window.

**`MIN_LEAD = 30 s`** gives about 2x headroom over roughly 13 s for the 3-second chains. Because of the round-up, the actual lead is 30 to 30+P seconds:
- quicknet and evmnet: 10-11 rounds ahead, and fulfillment is possible about 30-33 s after the request.
- `default` (P = 30): use `MIN_LEAD = 60 s` so the margin over `drand_early` is still positive with headroom.

Residual risk (stated, not mitigated on-chain): if AleoBFT stalls for more than `MIN_LEAD` between round `anchor-1` and commit, the target round may be published before the request is final. `final` cannot detect this. The parameter assumes AleoBFT partial-synchrony liveness with commit latency below 30 s.

Worked example, using testnet block 20682378 with `T = 1792560501` and `MIN_LEAD = 30`:

| Chain | `target_round` | `round_time` | lead | timeout eligible at |
|---|---|---|---|---|
| quicknet | 33252389 | 1792560531 | 30 s | 1792564131 |
| evmnet | 21679820 | 1792560532 | 31 s | 1792564132 |
| default | 6570984 | 1792560540 | 39 s (use MIN_LEAD 60 in practice) | 1792564140 |

Leo sketch (in `final`; `T > G` always holds because Aleo genesis is after every drand genesis):

```leo
let t: u64 = block.timestamp as u64;
let target: u64 = (t + MIN_LEAD - DRAND_GENESIS + DRAND_PERIOD - 1u64) / DRAND_PERIOD + 1u64;
```

## Request and domain binding

- `request_id`: a `u64` counter held in a service mapping and incremented in `final`. It is unique and set by the program, never by the caller.
- `consumer`: `self.caller`, captured in the proof context and passed to `final`. This lets one consumer program's requests be told apart from another's, even when they share a round.
- `consumer_tag: field`: an application-defined domain or sub-purpose (for example a hash of a game ID). It is stored with the request and is **only** a namespace. Requests stay distinct because of `request_id`.
- Stored per request: `{consumer, consumer_tag, target_round, requested_at: T, status}`.
- `out = BHP256::hash_to_field(RandomnessInput { domain: DOMAIN_V1, chain: CHAIN_ID, request_id, consumer, consumer_tag, round: target_round, sig })`. Here `sig` is the verified beacon signature (or its canonical encoding).
- Hash the **signature**, not drand's published `randomness` field. That field is `SHA-256(sig)`, and Leo has no SHA-256, so the program could not check it. The BLS signature is unique, so it carries the same entropy. The exact encoding depends on the verification-feasibility outcome.
- Two requests on the same round get independent-looking outputs because `request_id` differs. Anyone who knows the round can compute every output, which is acceptable because the round is public once published (map #1, third security criterion).

## Timeout

- **Eligible** when the request is unfulfilled and `block.timestamp >= round_time(target_round) + TIMEOUT_GRACE`.
- **`TIMEOUT_GRACE = 3600 s`**, about 1200 testnet blocks. It has to be much larger than:
  - the +10 s forward timestamp skew, which could otherwise fire a timeout early;
  - normal relayer latency (seconds);
  - short drand outages, which are recovered through catch-up.
- **Race rule:** fulfillment and timeout are mutually exclusive state transitions on `status`, and whichever finalizes first wins. Fulfillment stays valid after the deadline until a timeout is executed.
- **Selective-abort warning.** By the deadline, the target round is public, so the requester already knows the output. A timeout that refunds and lets the consumer retry with a fresh round is a re-roll, which means bias.
  - Mitigations: make fulfillment **permissionless**, so any party, including the requester's counterparty, can complete it; and say in the consumer docs that a timed-out request must not lead to a retry that favors the requester.
  - Consumer programs decide what timeout means (for example forfeit, or a neutral default). The service only releases fees.

## Assumptions (explicit)

- **A1 (Aleo):** Byzantine stake < 1/3. Honest validator clocks are within ±2 s of UTC. AleoBFT commit latency from round `anchor-1` is below about 8 s normally and always below `MIN_LEAD - aleo_clock_lag - P`.
- **D1 (drand):** drand threshold honesty holds. Honest drand node clocks are within about 1 s of UTC, so no round appears more than `P` before `TimeOfRound`.
- **D2 (drand):** the pinned chain's `(G, P)` never change. A drand reshare keeps the chain hash, genesis and period. A new chain would need a new service constant.
- **L1 (Leo/snarkVM):** `block.timestamp` in `final` is that of the block finalizing the transaction, and it is present (post-V12).

## Open items handed to other tickets

- Which chain to pin (quicknet, evmnet or default) and the on-chain signature encoding. These depend on "drand Verification Feasibility on Aleo".
- Fee and refund semantics on timeout belong to the service/consumer interface.
