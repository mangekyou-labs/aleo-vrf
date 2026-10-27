# drand Relay for Aleo: a trusted relay that delivers drand quicknet rounds to Aleo programs; the relayer is trusted, and every fulfillment is publicly auditable.

> Status: early. This repo holds the request-to-fulfill path only. Timeout refunds, admin transfer, the relayer worker, and the audit tool are still to come.

## Trust model

Read this before you build on the service.

- Aleo can't check a drand BLS signature on-chain (snarkVM has no pairing), so `drand_relay.aleo` accepts rounds from **one configured relayer** and does not check signatures. See [ADR 0001](docs/adr/0001-trusted-relay-drand.md).
- The relayer can delay or withhold delivery. It could also forge a round to choose an output. There is no on-chain penalty for that.
- On-chain, the program rejects only unauthorized submitters, mismatched rounds, replays, and wrong payee or fee arguments.
- Every fulfillment stores the round and the full beacon signature in public mappings, so anyone can re-check them against drand's quicknet public key after the fact and prove a forgery from public state alone.
- One admin configures the service and can upgrade the program until upgrades are renounced. See [ADR 0002](docs/adr/0002-admin-gated-custom-upgrade.md). The admin can pause new requests, but never fulfillment.

## How it works

1. A consumer program (or a wallet) calls `request(tag, fee)` and pays the fixed fee into escrow. The **handle** is `(caller, tag)`.
2. In `final`, the program derives the target round from the block timestamp: the first quicknet round published at least 30 s after the request's block.
3. The relayer waits for that round, checks it locally, and calls `fulfill(handle, round, sig, payee, fee)`.
4. The program stores `results[handle]`, which is the output, and `signatures[handle]`, which is the signature as three big-endian `u128` limbs. It then pays the stored fee to the relayer payee.

Output v1 is `Poseidon2::hash_to_field(OutputInput { domain, chain, request_id, consumer, tag, round, sig })`.

## Layout

| Path | What |
| --- | --- |
| `programs/drand_relay` | The service program, `drand_relay.aleo` |
| `programs/drand_relay_core` | Leo library: quicknet constants, round binding, output v1 |
| `packages/shared` | TS: `OutputInput` encoding, signature limb packing, quicknet constants |
| `packages/devnet` | SDK-driven end-to-end suite against a local devnet (local only) |

## Development

Requirements: Leo 4.4.4, Node 24, and pnpm 8.

```sh
pnpm install
pnpm test        # TS tests
pnpm test:leo    # leo test for both Leo packages
```

The devnet suite deploys the built program, requests, waits for the real drand round, and fulfills it:

```sh
leo build --path programs/drand_relay
leo devnet --snarkos <snarkos built with --features test_network> --snarkos-features test_network --clear-storage -y
pnpm test:devnet
```
