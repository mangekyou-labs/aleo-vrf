// drand_relay.aleo is a trusted relay: one configured relayer delivers drand quicknet rounds, and the program does not check them.
//
// Aleo can't check a drand BLS signature on-chain (snarkVM has no pairing), so
// the relayer can delay, withhold, or forge a round. Every fulfillment stores
// the round and the full signature in public mappings, so anyone can re-check
// it against quicknet's public key afterwards. See
// docs/adr/0001-trusted-relay-drand.md.
import credits.aleo;

const PENDING: u8 = 0u8;
const FULFILLED: u8 = 1u8;
const TIMED_OUT: u8 = 2u8;

// A request is keyed by the consumer that asked and its chosen tag.
export struct Handle {
    consumer: address,
    tag: field,
}

export struct Request {
    request_id: u64,
    round: u64,
    payer: address,
    fee: u64,
    status: u8,
}

// Shared by every admin setter.
final fn assert_admin(caller: address) {
    assert_eq(caller, admin.get(0u8));
}

program drand_relay.aleo {
    mapping requests: Handle => Request;
    mapping handles: u64 => Handle;
    mapping next_request_id: u8 => u64;
    // Written only by fulfill.
    mapping results: Handle => field;
    mapping signatures: Handle => [u128; 3];

    // Config singletons, all keyed by 0u8.
    mapping admin: u8 => address;
    mapping pending_admin: u8 => address;
    mapping relayer: u8 => address;
    mapping relayer_payee: u8 => address;
    mapping fee: u8 => u64;
    mapping paused: u8 => bool;
    mapping ossified: u8 => bool;

    // Edition 0: the deployer becomes admin and the service starts paused.
    // Later editions: only accepted from the admin, and never once ossified.
    @custom
    constructor() {
        if std::ctx::edition() == 0u16 {
            admin.set(0u8, std::ctx::program_owner());
            paused.set(0u8, true);
        } else {
            assert(!ossified.get_or_use(0u8, false));
            assert_eq(std::ctx::program_owner(), admin.get(0u8));
        }
    }

    // Ask for randomness under `tag`. The caller is the consumer; the signer
    // pays `fee`, which must equal the configured fee, into escrow.
    fn request(public tag: field, public fee_amount: u64) -> Final {
        let escrow: Final = credits.aleo::transfer_public_as_signer(std::ctx::addr(), fee_amount);
        let handle: Handle = Handle { consumer: std::ctx::caller(), tag: tag };
        let payer: address = std::ctx::signer();
        return final {
            assert(!paused.get(0u8));
            assert(!requests.contains(handle));
            assert_eq(fee_amount, fee.get(0u8));
            let id: u64 = next_request_id.get_or_use(0u8, 1u64);
            let round: u64 = drand_relay_core::target_round(std::ctx::block_timestamp());
            requests.set(handle, Request { request_id: id, round: round, payer: payer, fee: fee_amount, status: PENDING });
            handles.set(id, handle);
            next_request_id.set(0u8, id + 1u64);
            escrow.run();
        };
    }

    // The relayer delivers quicknet `round`'s signature for `handle`. The
    // signature is not checked on-chain (snarkVM has no pairing); the audit
    // re-checks it. The stored fee goes to the configured payee. `payee` and
    // `fee_amount` are arguments because the transfer happens in `fn`; `final`
    // asserts they match. Not pausable.
    fn fulfill(public handle: Handle, public round: u64, public sig: [u128; 3], public payee: address, public fee_amount: u64) -> Final {
        let payout: Final = credits.aleo::transfer_public(payee, fee_amount);
        let caller: address = std::ctx::caller();
        return final {
            assert_eq(caller, relayer.get(0u8));
            let req: Request = requests.get(handle);
            assert_eq(req.status, PENDING);
            assert_eq(round, req.round);
            assert_eq(payee, relayer_payee.get(0u8));
            assert_eq(fee_amount, req.fee);
            let output: field = drand_relay_core::output_v1(drand_relay_core::OutputInput {
                domain: drand_relay_core::OUTPUT_DOMAIN_V1,
                chain: drand_relay_core::QUICKNET_CHAIN,
                request_id: req.request_id,
                consumer: handle.consumer,
                tag: handle.tag,
                round: round,
                sig: sig,
            });
            results.set(handle, output);
            signatures.set(handle, sig);
            requests.set(handle, Request { request_id: req.request_id, round: req.round, payer: req.payer, fee: req.fee, status: FULFILLED });
            payout.run();
        };
    }

    // Output v1 for `input`, exactly as `fulfill` computes it. Pure, with no
    // `final`, so anyone can execute it to recompute an output, and an audit
    // can pin v1 against this entry point.
    fn output_v1(public input: drand_relay_core::OutputInput) -> field {
        return drand_relay_core::output_v1(input);
    }

    // Admin setters. Only a direct call from the admin passes: the caller must
    // be the admin, so a program the admin key happens to sign for can't
    // reconfigure the service behind the admin's back.
    fn set_relayer(public value: address) -> Final {
        let caller: address = std::ctx::caller();
        return final {
            assert_admin(caller);
            relayer.set(0u8, value);
        };
    }

    fn set_relayer_payee(public value: address) -> Final {
        let caller: address = std::ctx::caller();
        return final {
            assert_admin(caller);
            relayer_payee.set(0u8, value);
        };
    }

    // Zero is allowed.
    fn set_fee(public value: u64) -> Final {
        let caller: address = std::ctx::caller();
        return final {
            assert_admin(caller);
            fee.set(0u8, value);
        };
    }

    // Pause blocks `request` only; `fulfill` is never pausable.
    fn set_paused(public value: bool) -> Final {
        let caller: address = std::ctx::caller();
        return final {
            assert_admin(caller);
            paused.set(0u8, value);
        };
    }
}
