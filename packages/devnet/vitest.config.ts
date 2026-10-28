import { defineConfig } from "vitest/config";

// The suite drives a live local devnet with real proofs and waits for a real
// drand round, so steps take minutes, not milliseconds. It runs in order.
export default defineConfig({
  test: {
    testTimeout: 30 * 60 * 1000,
    hookTimeout: 30 * 60 * 1000,
    fileParallelism: false,
    sequence: { concurrent: false },
  },
});
