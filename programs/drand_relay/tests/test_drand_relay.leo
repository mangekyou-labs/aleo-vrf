// Tests for drand_relay.aleo, run on the real VM by `leo test`.
//
// Every @test fn starts from a freshly deployed program. The deployer, and so
// the admin, is the default test key
// aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px.
//
// leo test always calls drand_relay.aleo through this test program, so the
// callee sees caller == test_drand_relay.aleo, whatever key signs. The admin
// setters accept only caller == admin, so no test here can configure the
// service: it stays paused with no fee or relayer. Everything that needs a
// configured service (request, fulfill, pause) is covered by the devnet suite
// in packages/devnet. What leo test can pin is the deploy state and that the
// admin setters refuse any program caller.
import drand_relay.aleo;

program test_drand_relay.aleo {
    @test
    fn deploy_sets_admin_and_pause() -> Final {
        return final {
            assert_eq(Mapping::get(drand_relay.aleo::admin, 0u8), aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
            assert(Mapping::get(drand_relay.aleo::paused, 0u8));
        };
    }

    // The golden vector through the program's own output entry point. The same
    // input and output as drand_relay_core's golden_output_v1 and
    // packages/shared/test/output.test.ts.
    @test
    fn golden_output_v1_entry() {
        let input: drand_relay_core::OutputInput = drand_relay_core::OutputInput {
            domain: drand_relay_core::OUTPUT_DOMAIN_V1,
            chain: drand_relay_core::QUICKNET_CHAIN,
            request_id: 1u64,
            consumer: aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px,
            tag: 7field,
            round: 1000u64,
            sig: [
                239626968901406750420327125163575684777u128,
                235778950374705849948450593008868069669u128,
                302081162955922238783914645960155553337u128,
            ],
        };
        assert_eq(drand_relay.aleo::output_v1(input), 2970490141221046626481504361745901933087069281016493373753253154666567523302field);
    }

    // Signed by the admin key, but called through this program. The caller is
    // test_drand_relay.aleo, not the admin, so each setter must refuse. This is
    // the case of a program that the admin key signs for trying to reconfigure
    // the service.
    @test
    @should_fail
    fn admin_via_program_set_relayer() -> Final {
        let f: Final = drand_relay.aleo::set_relayer(std::ctx::addr());
        return final { f.run(); };
    }

    @test
    @should_fail
    fn admin_via_program_set_payee() -> Final {
        let f: Final = drand_relay.aleo::set_relayer_payee(std::ctx::addr());
        return final { f.run(); };
    }

    @test
    @should_fail
    fn admin_via_program_set_fee() -> Final {
        let f: Final = drand_relay.aleo::set_fee(0u64);
        return final { f.run(); };
    }

    @test
    @should_fail
    fn admin_via_program_unpause() -> Final {
        let f: Final = drand_relay.aleo::set_paused(false);
        return final { f.run(); };
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
