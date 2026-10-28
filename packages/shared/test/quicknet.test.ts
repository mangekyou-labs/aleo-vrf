import { describe, expect, it } from "vitest";
import { QUICKNET, roundTime, targetRound } from "../src/index.ts";

describe("quicknet constants", () => {
  it("match the published quicknet chain info", () => {
    // https://api.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/info
    expect(QUICKNET.chainHash).toBe("52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971");
    expect(QUICKNET.genesisTime).toBe(1692803367n);
    expect(QUICKNET.period).toBe(3n);
    expect(QUICKNET.minLead).toBe(30n);
  });

  it("splits the chain hash into two big-endian u128 limbs", () => {
    expect(QUICKNET.chainLimbs).toEqual([
      110136965675322143216349549528651941793n,
      326031929928472161355514053828752501105n,
    ]);
  });
});

describe("round binding", () => {
  it("round 1 is at genesis and each round is one period later", () => {
    expect(roundTime(1n)).toBe(1692803367n);
    expect(roundTime(1000n)).toBe(1692803367n + 999n * 3n);
  });

  it("picks the first round at least 30 s after the request", () => {
    // ts + 30 lands exactly on a round time: that round is allowed.
    expect(targetRound(1692803367n + 999n * 3n - 30n)).toBe(1000n);
    // One second later it is too early, so the next round is used.
    expect(targetRound(1692803367n + 999n * 3n - 29n)).toBe(1001n);
  });

  it("always satisfies round time >= ts + 30 within one period", () => {
    for (let ts = 1793000000n; ts < 1793000010n; ts++) {
      const t = roundTime(targetRound(ts));
      expect(t >= ts + 30n).toBe(true);
      expect(t < ts + 33n).toBe(true);
    }
  });
});
