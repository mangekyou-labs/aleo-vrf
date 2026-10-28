// Pure code shared by drand_relay.aleo and its tests: the quicknet constants,
// round binding, and output v1. A library is inlined into the program that
// uses it, so nothing here has its own on-chain footprint.

// drand quicknet: unix time of round 1, seconds per round, and how far ahead
// of the request's block the target round must be.
export const QUICKNET_GENESIS: i64 = 1692803367i64;
export const QUICKNET_PERIOD: i64 = 3i64;
export const MIN_LEAD: i64 = 30i64;

// The first quicknet round whose time is at least MIN_LEAD seconds after `ts`:
// round = ceil((ts + MIN_LEAD - G) / P) + 1, so round_time(round) >= ts + MIN_LEAD.
export fn target_round(ts: i64) -> u64 {
    let lead: u64 = (ts + MIN_LEAD - QUICKNET_GENESIS) as u64;
    let period: u64 = QUICKNET_PERIOD as u64;
    return (lead + period - 1u64) / period + 1u64;
}

// Unix time at which `round` is published.
export fn round_time(round: u64) -> i64 {
    return QUICKNET_GENESIS + ((round - 1u64) as i64) * QUICKNET_PERIOD;
}

// The quicknet chain hash 52db9ba7...0c84e971 as two big-endian u128 limbs.
export const QUICKNET_CHAIN: [u128; 2] = [110136965675322143216349549528651941793u128, 326031929928472161355514053828752501105u128];

// The ASCII bytes of "drand_relay.output.v1", big-endian. Pinned: changing it changes every output.
export const OUTPUT_DOMAIN_V1: field = 146803161469755026820848386157232654245934194914865field;

export struct OutputInput {
    domain: field,
    chain: [u128; 2],
    request_id: u64,
    consumer: address,
    tag: field,
    round: u64,
    sig: [u128; 3],
}

// Output v1. The audit recomputes this from public state.
export fn output_v1(input: OutputInput) -> field {
    return Poseidon2::hash_to_field(input);
}
