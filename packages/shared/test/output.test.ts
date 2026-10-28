import { describe, expect, it } from "vitest";
import { OUTPUT_DOMAIN_V1, computeOutput, encodeOutputInput } from "../src/index.ts";

// The golden vector. The same input and output are asserted in Leo in
// programs/drand_relay_core/tests/test_drand_relay_core.leo.
const GOLDEN = {
  requestId: 1n,
  consumer: "aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px",
  tag: 7n,
  round: 1000n,
  // Quicknet round 1000's real signature.
  signature: "b44679b9a59af2ec876b1a6b1ad52ea9b1615fc3982b19576350f93447cb1125e342b73a8dd2bacbe47e4b6b63ed5e39",
};
const GOLDEN_OUTPUT = "2970490141221046626481504361745901933087069281016493373753253154666567523302field";

describe("OutputInput", () => {
  it("uses the ASCII bytes of drand_relay.output.v1 as the domain", () => {
    expect(OUTPUT_DOMAIN_V1).toBe(146803161469755026820848386157232654245934194914865n);
  });

  it("encodes as the Leo plaintext of the OutputInput struct", () => {
    expect(encodeOutputInput(GOLDEN)).toBe(
      "{ domain: 146803161469755026820848386157232654245934194914865field, " +
        "chain: [110136965675322143216349549528651941793u128, 326031929928472161355514053828752501105u128], " +
        "request_id: 1u64, " +
        "consumer: aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px, " +
        "tag: 7field, " +
        "round: 1000u64, " +
        "sig: [239626968901406750420327125163575684777u128, 235778950374705849948450593008868069669u128, 302081162955922238783914645960155553337u128] }",
    );
  });

  it("hashes the golden vector to the same output as the Leo program", () => {
    expect(computeOutput(GOLDEN)).toBe(GOLDEN_OUTPUT);
  });

  it("changes the output when any bound field changes", () => {
    const base = computeOutput(GOLDEN);
    expect(computeOutput({ ...GOLDEN, requestId: 2n })).not.toBe(base);
    expect(computeOutput({ ...GOLDEN, tag: 8n })).not.toBe(base);
    expect(computeOutput({ ...GOLDEN, round: 1001n })).not.toBe(base);
    expect(
      computeOutput({ ...GOLDEN, consumer: "aleo1s3ws5tra87fjycnjrwsjcrnw2qxr8jfqqdugnf0xzqqw29q9m5pqem2u4t" }),
    ).not.toBe(base);
  });
});
