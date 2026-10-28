// Tests for the pure parts of the service: round binding and output v1.
program test_drand_relay_core.aleo {
    // The golden vector. packages/shared/test/output.test.ts asserts the same
    // input and output through the TS encoding and the SDK's Poseidon2.
    // The signature is quicknet round 1000's real signature
    // b44679b9...63ed5e39, packed big-endian into three u128 limbs.
    @test
    fn golden_output_v1() {
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
        assert_eq(drand_relay_core::output_v1(input), 2970490141221046626481504361745901933087069281016493373753253154666567523302field);
    }

    // Round 1000 is published at G + 999 * 3 = 1692806364.
    @test
    fn round_lands_exactly_on_lead() {
        assert_eq(drand_relay_core::target_round(1692806364i64 - 30i64), 1000u64);
        assert_eq(drand_relay_core::round_time(1000u64), 1692806364i64);
    }

    // One second later, round 1000 is only 29 s away, so the next round is used.
    @test
    fn round_never_closer_than_lead() {
        assert_eq(drand_relay_core::target_round(1692806364i64 - 29i64), 1001u64);
        assert_eq(drand_relay_core::target_round(1692806364i64 - 28i64), 1001u64);
        assert_eq(drand_relay_core::target_round(1692806364i64 - 27i64), 1001u64);
        assert_eq(drand_relay_core::target_round(1692806364i64 - 26i64), 1002u64);
    }

    @noupgrade
    constructor() {}
}
