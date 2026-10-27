import { bytesToBigInt, hexToBytes } from "./bytes.ts";

const CHAIN_HASH = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971";
const chainBytes = hexToBytes(CHAIN_HASH);

/** drand quicknet, the only beacon the service uses. Mirrors the constants in drand_relay_core. */
export const QUICKNET = {
  chainHash: CHAIN_HASH,
  /** The chain hash as [u128; 2], big-endian, as the program stores it. */
  chainLimbs: [bytesToBigInt(chainBytes.subarray(0, 16)), bytesToBigInt(chainBytes.subarray(16, 32))] as [
    bigint,
    bigint,
  ],
  /** Unix time of round 1. */
  genesisTime: 1692803367n,
  /** Seconds between rounds. */
  period: 3n,
  /** A request's round is at least this many seconds after the request's block. */
  minLead: 30n,
  /** BLS12-381 G2 public key, unchained RFC 9380 scheme (bls-unchained-g1-rfc9380). */
  publicKey:
    "83cf0f2896adee7eb8b5f01fcad3912212c437e0073e911fb90022d3e760183c8c4b450b6a0a6c3ac6a5776a2d1064510d1fec758c921cc22b0e17e63aaf4bcb5ed66304de9cf809bd274ca73bab4af5a6e9c76a4bc09e76eae8991ef5ece45a",
} as const;

/** Unix time at which `round` is published. */
export function roundTime(round: bigint): bigint {
  return QUICKNET.genesisTime + (round - 1n) * QUICKNET.period;
}

/**
 * The round the program assigns to a request finalized at block time `ts`:
 * ceil((ts + MIN_LEAD - G) / P) + 1, the first round with roundTime >= ts + MIN_LEAD.
 */
export function targetRound(ts: bigint): bigint {
  const lead = ts + QUICKNET.minLead - QUICKNET.genesisTime;
  return (lead + QUICKNET.period - 1n) / QUICKNET.period + 1n;
}
