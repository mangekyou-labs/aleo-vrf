import { describe, expect, it } from "vitest";
import { limbsToSignature, signatureToLimbs } from "../src/index.ts";

// Quicknet round 1000, from https://api.drand.sh/<quicknet chain hash>/public/1000
const ROUND_1000_SIG =
  "b44679b9a59af2ec876b1a6b1ad52ea9b1615fc3982b19576350f93447cb1125e342b73a8dd2bacbe47e4b6b63ed5e39";

describe("signature limb packing", () => {
  it("packs 48 bytes into three big-endian u128 limbs", () => {
    expect(signatureToLimbs(ROUND_1000_SIG)).toEqual([
      239626968901406750420327125163575684777n,
      235778950374705849948450593008868069669n,
      302081162955922238783914645960155553337n,
    ]);
  });

  it("accepts bytes as well as hex", () => {
    const bytes = Uint8Array.from(Buffer.from(ROUND_1000_SIG, "hex"));
    expect(signatureToLimbs(bytes)).toEqual(signatureToLimbs(ROUND_1000_SIG));
  });

  it("round-trips limbs back to the same 48 bytes", () => {
    const back = limbsToSignature(signatureToLimbs(ROUND_1000_SIG));
    expect(Buffer.from(back).toString("hex")).toBe(ROUND_1000_SIG);
  });

  it("keeps leading zero bytes", () => {
    const sig = "00".repeat(17) + "ff".repeat(31);
    const limbs = signatureToLimbs(sig);
    // 17 zero bytes: the whole first limb and the top byte of the second.
    expect(limbs).toEqual([0n, (1n << 120n) - 1n, (1n << 128n) - 1n]);
    expect(Buffer.from(limbsToSignature(limbs)).toString("hex")).toBe(sig);
  });

  it("rejects anything that is not 48 bytes", () => {
    expect(() => signatureToLimbs("ab".repeat(47))).toThrow(/48 bytes/);
    expect(() => signatureToLimbs(new Uint8Array(49))).toThrow(/48 bytes/);
  });

  it("rejects limbs outside u128", () => {
    expect(() => limbsToSignature([1n << 128n, 0n, 0n])).toThrow(/u128/);
    expect(() => limbsToSignature([-1n, 0n, 0n])).toThrow(/u128/);
  });
});
