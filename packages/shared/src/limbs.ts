// A drand quicknet signature is a 48-byte compressed BLS12-381 G1 point.
// On-chain it is stored as [u128; 3]: bytes 0..16, 16..32, 32..48, each read big-endian.

export type SignatureLimbs = [bigint, bigint, bigint];

const SIG_BYTES = 48;
const LIMB_BYTES = 16;
const U128_MAX = (1n << 128n) - 1n;

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(clean)) {
    throw new Error(`not a hex string: ${hex}`);
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Big-endian bytes -> unsigned integer. */
export function bytesToBigInt(bytes: Uint8Array): bigint {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  return n;
}

export function signatureToLimbs(signature: Uint8Array | string): SignatureLimbs {
  const bytes = typeof signature === "string" ? hexToBytes(signature) : signature;
  if (bytes.length !== SIG_BYTES) {
    throw new Error(`signature must be ${SIG_BYTES} bytes, got ${bytes.length}`);
  }
  return [0, 1, 2].map((i) => bytesToBigInt(bytes.subarray(i * LIMB_BYTES, (i + 1) * LIMB_BYTES))) as SignatureLimbs;
}

export function limbsToSignature(limbs: readonly bigint[]): Uint8Array {
  if (limbs.length !== 3) throw new Error(`expected 3 limbs, got ${limbs.length}`);
  const out = new Uint8Array(SIG_BYTES);
  limbs.forEach((limb, i) => {
    if (limb < 0n || limb > U128_MAX) throw new Error(`limb ${i} is not a u128: ${limb}`);
    let n = limb;
    for (let j = LIMB_BYTES - 1; j >= 0; j--) {
      out[i * LIMB_BYTES + j] = Number(n & 0xffn);
      n >>= 8n;
    }
  });
  return out;
}
