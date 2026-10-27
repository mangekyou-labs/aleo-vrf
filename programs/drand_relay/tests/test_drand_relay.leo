// Tests for drand_relay.aleo, run on the real VM by `leo test`.
//
// Every @test fn starts from a freshly deployed program, so each test does its
// own setup. The default test signer is the deployer (and so the admin):
// aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px.
// Calls from this test program reach drand_relay.aleo with
// caller == test_drand_relay.aleo's own address.
import credits.aleo;
import drand_relay.aleo;

program test_drand_relay.aleo {
    @test
    fn deploy_sets_admin_and_pause() -> Final {
        return final {
            assert_eq(Mapping::get(drand_relay.aleo::admin, 0u8), aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
            assert(Mapping::get(drand_relay.aleo::paused, 0u8));
        };
    }

    @test
    fn admin_configures_service() -> Final {
        let me: address = std::ctx::addr();
        let f1: Final = drand_relay.aleo::set_relayer(me);
        let f2: Final = drand_relay.aleo::set_relayer_payee(aleo1xl2zskxn7vvcx2sfz8v29kqu0tnvrlj2nd5xczmnh2xrcgajju9qgfrhhh);
        let f3: Final = drand_relay.aleo::set_fee(0u64);
        let f4: Final = drand_relay.aleo::set_paused(false);
        return final {
            f1.run();
            f2.run();
            f3.run();
            f4.run();
            assert_eq(Mapping::get(drand_relay.aleo::relayer, 0u8), me);
            assert_eq(Mapping::get(drand_relay.aleo::relayer_payee, 0u8), aleo1xl2zskxn7vvcx2sfz8v29kqu0tnvrlj2nd5xczmnh2xrcgajju9qgfrhhh);
            assert_eq(Mapping::get(drand_relay.aleo::fee, 0u8), 0u64);
            assert(!Mapping::get(drand_relay.aleo::paused, 0u8));
        };
    }

    @test
    fn request_escrows_and_records() -> Final {
        let me: address = std::ctx::addr();
        let payer: address = std::ctx::signer();
        let c1: Final = drand_relay.aleo::set_fee(10u64);
        let c2: Final = drand_relay.aleo::set_paused(false);
        let r: Final = drand_relay.aleo::request(7field, 10u64);
        return final {
            c1.run();
            c2.run();
            let before: u64 = Mapping::get_or_use(credits.aleo::account, payer, 0u64);
            r.run();
            let h: drand_relay.aleo::Handle = drand_relay.aleo::Handle { consumer: me, tag: 7field };
            let req: drand_relay.aleo::Request = Mapping::get(drand_relay.aleo::requests, h);
            assert_eq(req.request_id, 1u64);
            assert_eq(req.payer, payer);
            assert_eq(req.fee, 10u64);
            assert_eq(req.status, 0u8);
            assert_eq(Mapping::get(drand_relay.aleo::handles, 1u64), h);
            assert_eq(Mapping::get(drand_relay.aleo::next_request_id, 0u8), 2u64);
            // The fee moved from the payer into the service's own balance.
            assert_eq(Mapping::get_or_use(credits.aleo::account, payer, 0u64), before - 10u64);
            assert_eq(Mapping::get(credits.aleo::account, drand_relay.aleo), 10u64);
            // Round binding: quicknet G = 1692803367, P = 3, MIN_LEAD = 30.
            // The round's time is at least 30 s after the request, and within one period of that.
            let ts: i64 = std::ctx::block_timestamp();
            let round_time: i64 = 1692803367i64 + ((req.round - 1u64) as i64) * 3i64;
            assert(round_time >= ts + 30i64);
            assert(round_time < ts + 33i64);
        };
    }

    // Same setup as request_escrows_and_records, then the same tag again.
    @test
    @should_fail
    fn duplicate_tag_is_rejected() -> Final {
        let c1: Final = drand_relay.aleo::set_fee(10u64);
        let c2: Final = drand_relay.aleo::set_paused(false);
        let r1: Final = drand_relay.aleo::request(7field, 10u64);
        let r2: Final = drand_relay.aleo::request(7field, 10u64);
        return final {
            c1.run();
            c2.run();
            r1.run();
            r2.run();
        };
    }

    @test
    fn distinct_tags_get_next_ids() -> Final {
        let me: address = std::ctx::addr();
        let c1: Final = drand_relay.aleo::set_fee(10u64);
        let c2: Final = drand_relay.aleo::set_paused(false);
        let r1: Final = drand_relay.aleo::request(7field, 10u64);
        let r2: Final = drand_relay.aleo::request(8field, 10u64);
        return final {
            c1.run();
            c2.run();
            r1.run();
            r2.run();
            let h2: drand_relay.aleo::Handle = drand_relay.aleo::Handle { consumer: me, tag: 8field };
            assert_eq(Mapping::get(drand_relay.aleo::requests, h2).request_id, 2u64);
            assert_eq(Mapping::get(drand_relay.aleo::handles, 2u64), h2);
            assert_eq(Mapping::get(drand_relay.aleo::next_request_id, 0u8), 3u64);
            assert_eq(Mapping::get(credits.aleo::account, drand_relay.aleo), 20u64);
        };
    }

    // The service starts paused; configure everything except unpausing.
    @test
    @should_fail
    fn paused_blocks_request() -> Final {
        let c1: Final = drand_relay.aleo::set_fee(10u64);
        let r: Final = drand_relay.aleo::request(7field, 10u64);
        return final {
            c1.run();
            r.run();
        };
    }

    @test
    @should_fail
    fn request_fee_must_match_config() -> Final {
        let c1: Final = drand_relay.aleo::set_fee(10u64);
        let c2: Final = drand_relay.aleo::set_paused(false);
        let r: Final = drand_relay.aleo::request(7field, 9u64);
        return final {
            c1.run();
            c2.run();
            r.run();
        };
    }

    // A pending request has no result and no signature yet.
    @test
    fn pending_request_has_no_result() -> Final {
        let me: address = std::ctx::addr();
        let c1: Final = drand_relay.aleo::set_fee(10u64);
        let c2: Final = drand_relay.aleo::set_paused(false);
        let r: Final = drand_relay.aleo::request(7field, 10u64);
        return final {
            c1.run();
            c2.run();
            r.run();
            let h: drand_relay.aleo::Handle = drand_relay.aleo::Handle { consumer: me, tag: 7field };
            assert(!Mapping::contains(drand_relay.aleo::results, h));
            assert(!Mapping::contains(drand_relay.aleo::signatures, h));
        };
    }

    // Everything else is right (this program is the relayer, the payee and fee
    // match), but round 1 is not the stored round. leo test's block timestamp
    // is the wall clock, so no fixed round argument can match the stored one;
    // the positive fulfill path is covered by the devnet suite.
    @test
    @should_fail
    fn fulfill_wrong_round_rejected() -> Final {
        let me: address = std::ctx::addr();
        let c0: Final = drand_relay.aleo::set_relayer(me);
        let c1: Final = drand_relay.aleo::set_relayer_payee(aleo1xl2zskxn7vvcx2sfz8v29kqu0tnvrlj2nd5xczmnh2xrcgajju9qgfrhhh);
        let c2: Final = drand_relay.aleo::set_fee(0u64);
        let c3: Final = drand_relay.aleo::set_paused(false);
        let r: Final = drand_relay.aleo::request(7field, 0u64);
        let h: drand_relay.aleo::Handle = drand_relay.aleo::Handle { consumer: me, tag: 7field };
        let f: Final = drand_relay.aleo::fulfill(h, 1u64, [1u128, 2u128, 3u128], aleo1xl2zskxn7vvcx2sfz8v29kqu0tnvrlj2nd5xczmnh2xrcgajju9qgfrhhh, 0u64);
        return final {
            c0.run();
            c1.run();
            c2.run();
            c3.run();
            r.run();
            f.run();
        };
    }

    // Signed by a funded key that is not the admin.
    @test(private_key = "APrivateKey1zkp2RWGDcde3efb89rjhME1VYA8QMxcxep5DShNBR6n8Yjh")
    @should_fail
    fn non_admin_cannot_set_relayer() -> Final {
        let f: Final = drand_relay.aleo::set_relayer(std::ctx::addr());
        return final { f.run(); };
    }

    @test(private_key = "APrivateKey1zkp2RWGDcde3efb89rjhME1VYA8QMxcxep5DShNBR6n8Yjh")
    @should_fail
    fn non_admin_cannot_set_payee() -> Final {
        let f: Final = drand_relay.aleo::set_relayer_payee(std::ctx::signer());
        return final { f.run(); };
    }

    @test(private_key = "APrivateKey1zkp2RWGDcde3efb89rjhME1VYA8QMxcxep5DShNBR6n8Yjh")
    @should_fail
    fn non_admin_cannot_set_fee() -> Final {
        let f: Final = drand_relay.aleo::set_fee(0u64);
        return final { f.run(); };
    }

    @test(private_key = "APrivateKey1zkp2RWGDcde3efb89rjhME1VYA8QMxcxep5DShNBR6n8Yjh")
    @should_fail
    fn non_admin_cannot_unpause() -> Final {
        let f: Final = drand_relay.aleo::set_paused(false);
        return final { f.run(); };
    }

    @noupgrade
    constructor() {}
}
