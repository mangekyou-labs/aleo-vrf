"""Generate fpmul/src/main.leo: measurement transitions for research/drand-verification.md.

Usage: python3 -I gen.py <fp381|fp254|sha256_16|sha256_32|natives> > drand_<name>/src/main.leo

The output is a measurement aid, not a verifier. It emits straight-line Leo code for:
  * Montgomery (CIOS) multiplication modulo the BLS12-381 base field prime (6 x u64 limbs)
  * Montgomery (CIOS) multiplication modulo the BN254 base field prime (4 x u64 limbs)
  * SHA-256 compression truncated to 16 and 32 rounds (u32 words), to extrapolate 64 rounds
  * native Keccak-256 of a u64 (evmnet message digest input)
  * a native field multiplication baseline
"""

import sys

M64 = (1 << 64) - 1
P381 = 0x1A0111EA397FE69A4B1BA7B6434BACD764774B84F38512BF6730D2A0F6B0F6241EABFFFEB153FFFFB9FEFFFFFFFFAAAB
P254 = 0x30644E72E131A029B85045B68181585D97816A916871CA8D3C208C16D87CFD47


def limbs(p, n):
    return [(p >> (64 * i)) & M64 for i in range(n)]


def mont(name, p, n):
    pl = limbs(p, n)
    inv = (-pow(p, -1, 1 << 64)) % (1 << 64)
    out = []
    e = out.append
    counter = [0]

    def nv(base):
        counter[0] += 1
        return f"{base}_{counter[0]}"

    e(f"    // Montgomery CIOS multiplication modulo a {p.bit_length()}-bit prime, {n} x u64 limbs, u128 intermediates.")
    e(f"    transition {name}(a: [u64; {n}], b: [u64; {n}]) -> [u64; {n}] {{")
    e(f"        let M: u128 = {M64}u128;")
    for j in range(n + 2):
        e(f"        let t{j}_0: u64 = 0u64;")
    cur = [f"t{j}_0" for j in range(n + 2)]
    for i in range(n):
        c = "0u64"
        for j in range(n):
            x = nv("x")
            e(f"        let {x}: u128 = ({cur[j]} as u128) + (a[{j}u32] as u128) * (b[{i}u32] as u128) + ({c} as u128);")
            t = nv(f"t{j}")
            e(f"        let {t}: u64 = ({x} & M) as u64;")
            cur[j] = t
            c = nv("c")
            e(f"        let {c}: u64 = ({x} >> 64u8) as u64;")
        x = nv("x")
        e(f"        let {x}: u128 = ({cur[n]} as u128) + ({c} as u128);")
        t = nv(f"t{n}")
        e(f"        let {t}: u64 = ({x} & M) as u64;")
        cur[n] = t
        t = nv(f"t{n + 1}")
        e(f"        let {t}: u64 = ({x} >> 64u8) as u64;")
        cur[n + 1] = t
        m = nv("m")
        e(f"        let {m}: u64 = {cur[0]}.mul_wrapped({inv}u64);")
        x = nv("x")
        e(f"        let {x}: u128 = ({cur[0]} as u128) + ({m} as u128) * {pl[0]}u128;")
        c = nv("c")
        e(f"        let {c}: u64 = ({x} >> 64u8) as u64;")
        for j in range(1, n):
            x = nv("x")
            e(f"        let {x}: u128 = ({cur[j]} as u128) + ({m} as u128) * {pl[j]}u128 + ({c} as u128);")
            t = nv(f"t{j - 1}")
            e(f"        let {t}: u64 = ({x} & M) as u64;")
            cur[j - 1] = t
            c = nv("c")
            e(f"        let {c}: u64 = ({x} >> 64u8) as u64;")
        x = nv("x")
        e(f"        let {x}: u128 = ({cur[n]} as u128) + ({c} as u128);")
        t = nv(f"t{n - 1}")
        e(f"        let {t}: u64 = ({x} & M) as u64;")
        cur[n - 1] = t
        t = nv(f"t{n}")
        e(f"        let {t}: u64 = {cur[n + 1]} + (({x} >> 64u8) as u64);")
        cur[n] = t
    # Conditional final subtraction: r = t - p if t >= p.
    borrow = "0u128"
    d = []
    for j in range(n):
        x = nv("s")
        e(f"        let {x}: u128 = ({cur[j]} as u128) + 18446744073709551616u128 - {pl[j]}u128 - {borrow};")
        dj = nv("d")
        e(f"        let {dj}: u64 = ({x} & M) as u64;")
        d.append(dj)
        b = nv("bw")
        e(f"        let {b}: u128 = ({x} >> 64u8) == 0u128 ? 1u128 : 0u128;")
        borrow = b
    e(f"        let ge: bool = ({cur[n]} != 0u64) || ({borrow} == 0u128);")
    outs = ", ".join(f"ge ? {d[j]} : {cur[j]}" for j in range(n))
    e(f"        return [{outs}];")
    e("    }")
    return "\n".join(out)


K = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
]


def rotr(x, n):
    return f"(({x} >> {n}u8) | {x}.shl_wrapped({32 - n}u8))"


def sha(rounds=64):
    out = []
    e = out.append
    e(f"    // SHA-256 compression truncated to {rounds} of 64 rounds, u32 words, fully unrolled.")
    e("    // Leo 3.4 caps programs at 100,000 bytes, so the full 64 rounds do not fit in one program.")
    e(f"    transition sha256_{rounds}_rounds(h: [u32; 8], blk: [u32; 16]) -> [u32; 8] {{")
    w = []
    for i in range(16):
        e(f"        let w{i}: u32 = blk[{i}u32];")
        w.append(f"w{i}")
    for i in range(16, rounds):
        a = w[i - 15]
        b = w[i - 2]
        e(
            f"        let w{i}: u32 = (({rotr(a, 7)} ^ {rotr(a, 18)} ^ ({a} >> 3u8)).add_wrapped({w[i - 16]}))"
            f".add_wrapped(({rotr(b, 17)} ^ {rotr(b, 19)} ^ ({b} >> 10u8)).add_wrapped({w[i - 7]}));"
        )
        w.append(f"w{i}")
    v = ["a", "b", "c", "d", "e", "f", "g", "hh"]
    for j in range(8):
        e(f"        let {v[j]}_0: u32 = h[{j}u32];")
    s = [f"{v[j]}_0" for j in range(8)]
    for i in range(rounds):
        A, B, C, D, E, F, G, H = s
        e(f"        let s1_{i}: u32 = {rotr(E, 6)} ^ {rotr(E, 11)} ^ {rotr(E, 25)};")
        e(f"        let ch_{i}: u32 = ({E} & {F}) ^ ((!{E}) & {G});")
        e(f"        let t1_{i}: u32 = {H}.add_wrapped(s1_{i}).add_wrapped(ch_{i}).add_wrapped({K[i]}u32).add_wrapped({w[i]});")
        e(f"        let s0_{i}: u32 = {rotr(A, 2)} ^ {rotr(A, 13)} ^ {rotr(A, 22)};")
        e(f"        let mj_{i}: u32 = ({A} & {B}) ^ ({A} & {C}) ^ ({B} & {C});")
        e(f"        let na_{i}: u32 = t1_{i}.add_wrapped(s0_{i}.add_wrapped(mj_{i}));")
        e(f"        let ne_{i}: u32 = {D}.add_wrapped(t1_{i});")
        s = [f"na_{i}", A, B, C, f"ne_{i}", E, F, G]
    outs = ", ".join(f"h[{j}u32].add_wrapped({s[j]})" for j in range(8))
    e(f"        return [{outs}];")
    e("    }")
    return "\n".join(out)


TAIL = """    // Native Keccak-256 over a 64-bit round number (the evmnet message digest input).
    transition keccak_round(round: u64) -> [bool; 256] {
        return Keccak256::hash_to_bits_raw(round);
    }

    // I/O baselines: same input/output shapes as the measured transitions, no arithmetic.
    transition io_fp381(a: [u64; 6], b: [u64; 6]) -> [u64; 6] {
        return a;
    }

    transition io_fp254(a: [u64; 4], b: [u64; 4]) -> [u64; 4] {
        return a;
    }

    transition io_sha256(h: [u32; 8], blk: [u32; 16]) -> [u32; 8] {
        return h;
    }

    // Baseline: native field multiplication, for comparison with emulated Fp multiplication.
    transition native_field_mul(a: field, b: field) -> field {
        return a * b;
    }"""


PROGRAMS = {
    "fp381": lambda: mont("fp381_mul", P381, 6),
    "fp254": lambda: mont("fp254_mul", P254, 4),
    "sha256_16": lambda: sha(16),
    "sha256_32": lambda: sha(32),
    "natives": lambda: TAIL,
}


def main():
    # One program per building block: Leo 3.4 rejects programs above 100,000 bytes.
    name = sys.argv[1]
    body = PROGRAMS[name]()
    print(
        "// Measurement prototype for research/drand-verification.md.\n"
        "// Generated by ../gen.py. Not a verifier: it only measures the cost of the building\n"
        "// blocks a non-native drand BLS check would need inside an Aleo proof.\n"
        f"program drand_{name}.aleo {{\n"
        "    @noupgrade\n"
        "    async constructor() {}\n\n"
        f"{body}\n"
        "}"
    )


if __name__ == "__main__":
    main()
