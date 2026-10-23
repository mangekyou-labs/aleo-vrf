# Continue as a trusted-relay drand service

Aleo cannot check a drand round on-chain today: snarkVM has no pairing opcode or BLS12-381, and pairing checks in `fn` or `final` are infeasible (see [drand Verification Feasibility on Aleo](https://github.com/mangekyou-labs/aleo-vrf/issues/3)). We continue anyway, as a service named a **trusted relay**: the program accepts rounds only from one configured relayer and does not check beacon signatures. The relayer can delay or withhold delivery (capped by the timeout refund) and could forge a round to choose an output. There is no on-chain penalty, because a fraud proof would itself need the BLS check we cannot do. Instead, every fulfillment stores the round number and full beacon signature in public state, and an open-source audit tool re-checks them against drand's public key, so forgery is publicly provable after the fact.

## Considered Options

- **Stop** until on-chain verification exists. Rejected: the remaining avenue (Varuna `snark.verify` over an off-chain pairing circuit) is an unbuilt spike of unknown cost.
- **Make the Varuna spike a prerequisite.** Rejected for this destination; it is named in the docs as the future path to removing the relayer trust.
- **k-of-n relayer attestation.** Deferred: it multiplies key management, attestation cost, and operations, and is out of scope for the testnet destination.

## Consequences

- Names, program identifiers, and docs never say "VRF", "verifiable", or "trustless". The service is "drand Relay for Aleo", and the first line of the README and program docs states the trust model.
- On-chain rejection covers mismatched rounds, replays, and unauthorized submitters only. Detecting an invalid (forged) round is off-chain, by audit.
