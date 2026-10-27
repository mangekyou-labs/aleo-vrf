import { Plaintext, Poseidon2 } from "@provablehq/sdk";
import { signatureToLimbs } from "./limbs.ts";
import { QUICKNET } from "./quicknet.ts";

/** The ASCII bytes of "drand_relay.output.v1", big-endian, as a field. Pinned: changing it changes every output. */
export const OUTPUT_DOMAIN_V1 = 146803161469755026820848386157232654245934194914865n;

export interface OutputParams {
  requestId: bigint;
  consumer: string;
  tag: bigint;
  round: bigint;
  /** 48-byte signature, as bytes or hex. */
  signature: Uint8Array | string;
}

/** The Leo plaintext of `OutputInput`, field order as declared in drand_relay_core. */
export function encodeOutputInput(p: OutputParams): string {
  const [c0, c1] = QUICKNET.chainLimbs;
  const [s0, s1, s2] = signatureToLimbs(p.signature);
  return (
    `{ domain: ${OUTPUT_DOMAIN_V1}field, ` +
    `chain: [${c0}u128, ${c1}u128], ` +
    `request_id: ${p.requestId}u64, ` +
    `consumer: ${p.consumer}, ` +
    `tag: ${p.tag}field, ` +
    `round: ${p.round}u64, ` +
    `sig: [${s0}u128, ${s1}u128, ${s2}u128] }`
  );
}

/**
 * Output v1 = Poseidon2 hash_to_field(OutputInput), exactly as the program
 * computes it. Returns the Leo literal, e.g. "123...field".
 */
export function computeOutput(p: OutputParams): string {
  const fields = Plaintext.fromString(encodeOutputInput(p)).toFields();
  return new Poseidon2().hash(fields).toString();
}
