---
name: aleo-docs
description: Local, greppable copy of the Aleo developer docs (docs.aleo.org/build). Use when writing or reviewing Leo programs (syntax, operators, crypto ops, finalization, mappings, limits), using the Leo CLI or a devnet, using the Provable SDK (@provablehq/sdk) from Node or the browser, or integrating the Aleo wallet adapter.
---

# Aleo docs (vendored)

docs.aleo.org sits behind a Cloudflare challenge that blocks `curl`; this folder is the same markdown, taken from the source repos. Search it with `grep -rn <term> references/`, then read the one file that answers. Use the index below to pick a file by its title.

Snapshot (2026-10-21). If something here contradicts observed tool behaviour, the docs may be stale. Re-vendor from:
- `references/leo/`: [ProvableHQ/leo-docs-source](https://github.com/ProvableHQ/leo-docs-source) `documentation/` @ `54c4d15` (Leo 4.x, served at docs.aleo.org/build/leo)
- `references/sdk/`: [ProvableHQ/sdk](https://github.com/ProvableHQ/sdk) `docs/` @ `f69db59` (served at docs.aleo.org/build/sdk)
- `references/wallet/`: [ProvableHQ/aleo-dev-toolkit](https://github.com/ProvableHQ/aleo-dev-toolkit) docs + package READMEs @ `37aff6c`

## Gotchas worth knowing before you search

- **Two execution contexts.** Plain `fn` runs off-chain inside the ZK proof, with private inputs. `final { }` blocks and `final fn` run on-chain, in public, and are the only place that can read or write mappings and storage (`guides/01_finalization.md`). Leo 4.0 renamed the 3.x `transition`/`async`/`finalize` terms; when old examples conflict, see `guides/11_migration_3_5_to_4_0.md`.
- **Native crypto** (`language/operators/cryptographic_operators.md`): BHP/Pedersen/Poseidon hashes and commitments, Keccak/SHA3, Schnorr `signature::verify` (Aleo addresses), and `ECDSA::verify_*` (secp256k1, Ethereum-style). `ChaCha::rand_*` gives validator-supplied randomness and works only in `final` context. There is **no pairing or BLS12-381 operator**. Aleo's own curve is BLS12-377 (`group`, `scalar`, `field`).
- **Hard limits** (`language/programs_in_practice/limitations.md`): 100 KB program, 31 functions, 31 mappings, 128 KB transaction, 100_000_000 microcredits of on-chain execution per transaction.

## Index

- `references/leo/00_leo.md`: The Leo Programming Language
- `references/leo/01_new.md`: What's new on Leo?
- `references/leo/02_where.md`: Where to go?
- `references/leo/cli/00_overview.md`: The Leo Command Line Interface
- `references/leo/cli/01_account.md`
- `references/leo/cli/02_add.md`
- `references/leo/cli/03_build.md`
- `references/leo/cli/04_clean.md`
- `references/leo/cli/05_debug.md`
- `references/leo/cli/06_deploy.md`
- `references/leo/cli/07_devnet.md`
- `references/leo/cli/08_execute.md`
- `references/leo/cli/09_new.md`
- `references/leo/cli/10_query.md`
- `references/leo/cli/11_remove.md`
- `references/leo/cli/12_run.md`
- `references/leo/cli/13_test.md`
- `references/leo/cli/14_update.md`
- `references/leo/cli/15_upgrade.md`
- `references/leo/cli/16_synthesize.md`
- `references/leo/cli/17_fmt.md`
- `references/leo/cli/18_plugins.md`
- `references/leo/getting_started/01_installation.md`: Installation
- `references/leo/getting_started/02_ide.md`: Your Development Environment
- `references/leo/getting_started/03_hello.md`: Hello, Leo
- `references/leo/guides/00_overview.md`: Overview
- `references/leo/guides/01_finalization.md`: The Finalization Model
- `references/leo/guides/02_dependencies.md`: Dependency Management
- `references/leo/guides/03_deploying.md`: Deploying Your Programs
- `references/leo/guides/04_executing.md`: Executing Your Programs
- `references/leo/guides/05_signing.md`: Signing and Verifying
- `references/leo/guides/06_query.md`: Querying Network Metadata and State
- `references/leo/guides/07_devnet.md`: Running a Devnet
- `references/leo/guides/08_testing.md`: Testing, Testing, 123
- `references/leo/guides/09_program_upgradability.md`: Upgrading Programs
- `references/leo/guides/10_abi.md`: ABI Generation
- `references/leo/guides/11_migration_3_5_to_4_0.md`: Migrating from Leo 3.5 to 4.0
- `references/leo/language/00_overview.md`: The Leo Language Reference
- `references/leo/language/01_layout.md`: Layout of a Leo Project
- `references/leo/language/02_structure.md`: Structure of a Leo Program
- `references/leo/language/03_data_types.md`: Data Types
- `references/leo/language/04_operators.md`: Operators & Expressions
- `references/leo/language/05_control_flow.md`: Control Flow
- `references/leo/language/06_libraries.md`: Leo Libraries
- `references/leo/language/07_style.md`: Best Practices
- `references/leo/language/08_cheatsheet.md`: Leo Syntax Cheatsheet
- `references/leo/language/operators/cryptographic_operators.md`: Cryptographic Operators
- `references/leo/language/operators/standard_operators.md`: Standard Operators
- `references/leo/language/programs_in_practice/control_flow.md`: Control Flow
- `references/leo/language/programs_in_practice/functions.md`: Functions
- `references/leo/language/programs_in_practice/interfaces.md`: Interfaces, Dynamic Calls & Dynamic Records
- `references/leo/language/programs_in_practice/intrinsics.md`: Intrinsics
- `references/leo/language/programs_in_practice/limitations.md`: Limitations
- `references/leo/language/programs_in_practice/private_storage.md`: Private State
- `references/leo/language/programs_in_practice/public_storage.md`: Public State
- `references/leo/leo_by_example/01_auction.md`: A Private Auction using Leo
- `references/leo/leo_by_example/02_basic_bank.md`: A Basic Bank using Leo
- `references/leo/leo_by_example/03_vote.md`: A Voting Program using Leo
- `references/leo/leo_by_example/04_token.md`: A Custom Token in Leo
- `references/leo/leo_by_example/05_tictactoe.md`: A Game of Tic-Tac-Toe in Leo
- `references/leo/leo_by_example/06_battleship.md`: A Game of Battleship in Leo
- `references/leo/resources/01_curated.md`: Curated Resources
- `references/leo/resources/02_projects.md`: Built on Leo
- `references/sdk/00_overview.md`: SDK for Building Zero-Knowledge Web Apps
- `references/sdk/adr/001-cjs-support.md`: ADR-001: CommonJS Build Target
- `references/sdk/api_reference/sdk-src_account.md`: Module `src/account`
- `references/sdk/api_reference/sdk-src_function-key-provider.md`: Module `src/function-key-provider`
- `references/sdk/api_reference/sdk-src_network-client.md`: Module `src/network-client`
- `references/sdk/api_reference/sdk-src_offline-key-provider.md`: Module `src/offline-key-provider`
- `references/sdk/api_reference/sdk-src_program-manager.md`: Module `src/program-manager`
- `references/sdk/api_reference/sdk-src_record-provider.md`: Module `src/record-provider`
- `references/sdk/api_reference/sdk-src_wasm.md`: Module `src/wasm`
- `references/sdk/api_reference/toc.md`: Code documentation
- `references/sdk/create-leo-app/01_intro.md`: **Create Leo App**
- `references/sdk/create-leo-app/02_react_js_tutorial.md`: React + Aleo + Leo
- `references/sdk/examples/01_transfer_public.md`
- `references/sdk/examples/02_transfer_private.md`
- `references/sdk/examples/03_deploy_program.md`
- `references/sdk/examples/04_execute_program.md`
- `references/sdk/guide/01_intro.md`: Intro to Aleo via the Provable SDK
- `references/sdk/guide/02_setup.md`: Zero-Knowledge JS App Setup
- `references/sdk/guide/03_creating_accounts.md`: Creating and Managing Aleo Accounts
- `references/sdk/guide/04_programs.md`: Aleo Programs and Transactions
- `references/sdk/guide/05_transfers.md`: Aleo Credit Transfers
- `references/sdk/guide/06_executing_programs.md`: Executing Aleo Programs
- `references/sdk/guide/07_deploying_programs.md`: Deploying Programs
- `references/sdk/guide/08_public_program_state.md`: Mappings - Persistent Public Program State
- `references/sdk/guide/09_private_program_state.md`: Records - Persistent Private Program State
- `references/sdk/guide/10_finding_records.md`: Finding Records
- `references/sdk/guide/11_working_with_chain_state.md`: Working with Chain State
- `references/wallet/migrating-to-adapter.md`: Migrating from `adaptor` to `adapter`
- `references/wallet/pkg-aleo-types.md`: @provablehq/aleo-types
- `references/wallet/pkg-aleo-wallet-adapter-react.md`: @provablehq/aleo-wallet-adapter-react
- `references/wallet/pkg-aleo-wallet-adapter.md`: Aleo Wallet Adapter
- `references/wallet/pkg-aleo-wallet-algorithms.md`: Aleo wallet algorithms
- `references/wallet/pkg-aleo-wallet-standard.md`
- `references/wallet/privacy-preserving-dapps.md`: Privacy-Preserving Dapps
- `references/wallet/wallet-adapter.md`: Aleo Wallet Adapter
- `references/wallet/wallet-hosted-algorithms-integration.md`: Integrate wallet-hosted algorithms
- `references/wallet/wallet-private-inputs.md`: Wallet private inputs
