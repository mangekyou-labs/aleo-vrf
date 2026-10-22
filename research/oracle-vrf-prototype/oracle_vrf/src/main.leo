// Oracle VRF cost prototype (research for issue #11).
// Every transition has the same public/private I/O shape so that
// marginal cost = measured - io_baseline.
program oracle_vrf.aleo {
    struct DleqTranscript {
        h: group,
        pk: group,
        gamma: group,
        u: group,
        v: group,
    }

    @noupgrade
    async constructor() {}

    // I/O baseline: same inputs and output, no crypto.
    transition io_baseline(public alpha: field, public pk: group, sk: scalar) -> public field {
        return alpha;
    }

    // Key check only: sk * G == pk.
    transition key_check(public alpha: field, public pk: group, sk: scalar) -> public field {
        assert_eq(sk * group::GEN, pk);
        return alpha;
    }

    // (a) Proof-as-VRF, Poseidon hash-to-group (recommended).
    // gamma stays private; only beta is public.
    transition vrf_psd2(public alpha: field, public pk: group, sk: scalar) -> public field {
        assert_eq(sk * group::GEN, pk);
        let h: group = Poseidon2::hash_to_group(alpha);
        let gamma: group = sk * h;
        return Poseidon2::hash_to_field(gamma);
    }

    // (a') Same with BHP256 hash-to-group (comparison only; BHP is linear, see doc).
    transition vrf_bhp256(public alpha: field, public pk: group, sk: scalar) -> public field {
        assert_eq(sk * group::GEN, pk);
        let h: group = BHP256::hash_to_group(alpha);
        let gamma: group = sk * h;
        return BHP256::hash_to_field(gamma);
    }

    // (a'') Proof-as-VRF with an on-chain check that alpha and pk match stored state.
    mapping oracle_pk: bool => group;
    mapping pending_alpha: field => bool;

    async transition vrf_psd2_fulfill(public alpha: field, public pk: group, sk: scalar) -> (public field, Future) {
        assert_eq(sk * group::GEN, pk);
        let h: group = Poseidon2::hash_to_group(alpha);
        let gamma: group = sk * h;
        let beta: field = Poseidon2::hash_to_field(gamma);
        return (beta, finalize_fulfill(alpha, pk, beta));
    }

    async function finalize_fulfill(alpha: field, pk: group, beta: field) {
        assert_eq(oracle_pk.get(true), pk);
        assert(pending_alpha.get(alpha));
        pending_alpha.remove(alpha);
    }

    // (b) ECVRF-style DLEQ verified in final. The proof (gamma, c, s) is made off-chain.
    async transition dleq_fulfill(public alpha: field, public gamma: group, public c: scalar, public s: scalar) -> Future {
        return finalize_dleq(alpha, gamma, c, s);
    }

    async function finalize_dleq(alpha: field, gamma: group, c: scalar, s: scalar) {
        let pk: group = oracle_pk.get(true);
        assert(pending_alpha.get(alpha));
        let h: group = Poseidon2::hash_to_group(alpha);
        let u: group = s * group::GEN - c * pk;
        let v: group = s * h - c * gamma;
        let t: DleqTranscript = DleqTranscript { h: h, pk: pk, gamma: gamma, u: u, v: v };
        let c2: scalar = Poseidon4::hash_to_scalar(t);
        assert_eq(c, c2);
        pending_alpha.remove(alpha);
    }
}
