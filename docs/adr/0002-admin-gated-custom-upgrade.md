# Admin-gated upgrades through a custom constructor

An Aleo program's constructor is fixed at first deployment and can never change, so the upgrade policy chosen at deploy is permanent. We use an `@custom` constructor. Edition 0 deploys freely. Every later edition must be submitted by the address stored in the service's `admin` mapping (`self.program_owner == admin`). The admin can be rotated by a two-step transfer (`propose_admin` → `accept_admin`). It can ossify the program with a one-way `renounce_upgrades()`, which sets an `ossified` flag that the constructor checks to reject every later edition. A transfer to a burn address can't work, because the two-step transfer needs the new admin to call `accept_admin`. Ossifying freezes the code only: the admin keeps the relayer, payee, fee, and pause setters, so a lost relayer key never kills the service. Upgrade authority is part of the trust model: an upgrade can rewrite `fulfill` and `timeout` logic, which also governs the fee escrow, so the README's trust section states this next to the relayer's powers.

## Considered Options

- **`@noupgrade`.** Safest, but any testnet bug forces a redeploy under a new program id, and every consumer and pending request must migrate.
- **`@admin(address=…)`.** The admin is hardcoded into the immutable constructor, so a lost or leaked admin key could never be rotated.
- **`@checksum` with a governance program.** Needs a separate DAO or multisig program, which is too heavy for a single-operator testnet pilot.
- **A time-lock on upgrades.** Deferred as later hardening; not needed for the testnet destination.

## Consequences

- The admin key is held out-of-band (personal wallet) and never on the relayer host. It also sets the relayer, relayer payee, and fee, and can pause new requests only. `fulfill` and `timeout` are never pausable.
- Users must trust the admin not to push a malicious upgrade until the program is ossified, and must trust the admin's configuration powers even after ossification.
