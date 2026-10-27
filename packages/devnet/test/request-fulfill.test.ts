// End-to-end request -> fulfill on a local devnet, driven through the SDK with
// real proofs and a real drand quicknet round. A local gate, not run in CI.
//
// Prerequisites:
//   1. `leo build --path programs/drand_relay` (the suite deploys the built bytecode).
//   2. A devnet on http://localhost:3030 (override with DEVNET_ENDPOINT), e.g.
//      leo devnet --snarkos <snarkos built with --features test_network> \
//        --snarkos-features test_network --clear-storage -y
//
// The suite plays every role with the devnet's funded dev accounts: account 0
// deploys (and so is admin), account 1 is the relayer, account 2 requests as a
// wallet (so it is both consumer and payer), account 3 is an outsider. The
// payee is a fresh address, so its balance is exactly the fees it was paid.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  Account,
  AleoNetworkClient,
  ProgramManager,
  getOrInitConsensusVersionTestHeights,
} from "@provablehq/sdk";
import { computeOutput, roundTime, signatureToLimbs, QUICKNET } from "@drand-relay/shared";
import { beforeAll, describe, expect, it } from "vitest";

const ENDPOINT = process.env.DEVNET_ENDPOINT ?? "http://localhost:3030";
const PROGRAM = "drand_relay.aleo";
const BYTECODE = fileURLToPath(new URL("../../../programs/drand_relay/build/drand_relay/drand_relay.aleo", import.meta.url));
// snarkVM's test_network consensus heights (V1 at 0, then V2.. at 5, 6, ...).
const TEST_HEIGHTS = process.env.CONSENSUS_VERSION_HEIGHTS ?? [0, ...Array.from({ length: 21 }, (_, i) => i + 5)].join(",");

const DEV_KEYS = [
  "APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH",
  "APrivateKey1zkp2RWGDcde3efb89rjhME1VYA8QMxcxep5DShNBR6n8Yjh",
  "APrivateKey1zkp2GUmKbVsuc1NSj28pa1WTQuZaK5f1DQJAT6vPcHyWokG",
  "APrivateKey1zkpBjpEgLo4arVUkQmcLdKQMiAKGaHAQVVwmF8HQby8vdYs",
];
const admin = new Account({ privateKey: DEV_KEYS[0] });
const relayer = new Account({ privateKey: DEV_KEYS[1] });
const consumer = new Account({ privateKey: DEV_KEYS[2] });
const outsider = new Account({ privateKey: DEV_KEYS[3] });
const payee = new Account();

const FEE = 1_000n; // microcredits
// A fresh tag per run, so the suite also runs against an already-deployed program.
const TAG = BigInt(Date.now());

const client = new AleoNetworkClient(ENDPOINT);
const manager = new ProgramManager(ENDPOINT);

type Outcome = "accepted" | "rejected";

async function confirmed(txId: string): Promise<{ status: Outcome; blockTimestamp: bigint }> {
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline) {
    const res = await fetch(`${ENDPOINT}/testnet/transaction/confirmed/${txId}`);
    if (res.ok) {
      const { status } = (await res.json()) as { status: Outcome };
      const hash = (await (await fetch(`${ENDPOINT}/testnet/find/blockHash/${txId}`)).json()) as string;
      const block = (await (await fetch(`${ENDPOINT}/testnet/block/${hash}`)).json()) as {
        header: { metadata: { timestamp: number } };
      };
      return { status, blockTimestamp: BigInt(block.header.metadata.timestamp) };
    }
    await sleep(2000);
  }
  throw new Error(`transaction ${txId} was not confirmed in time`);
}

async function exec(signer: Account, functionName: string, inputs: string[]) {
  const txId = await manager.execute({
    programName: PROGRAM,
    functionName,
    inputs,
    priorityFee: 0,
    privateFee: false,
    privateKey: signer.privateKey(),
  });
  return confirmed(txId);
}

async function mapping(name: string, key: string): Promise<string | null> {
  const v = await client.getProgramMappingValue(PROGRAM, name, key);
  return v === null || v === "null" ? null : String(v);
}

async function balance(address: string): Promise<bigint> {
  const raw = await client.getProgramMappingValue("credits.aleo", "account", address);
  return raw && raw !== "null" ? BigInt(String(raw).replace("u64", "")) : 0n;
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function drandRound(round: bigint): Promise<string> {
  const wait = Number(roundTime(round)) * 1000 - Date.now();
  if (wait > 0) await sleep(wait + 1500);
  for (let i = 0; i < 20; i++) {
    const res = await fetch(`https://api.drand.sh/${QUICKNET.chainHash}/public/${round}`);
    if (res.ok) {
      const body = (await res.json()) as { round: number; signature: string };
      expect(BigInt(body.round)).toBe(round);
      return body.signature;
    }
    await sleep(1500);
  }
  throw new Error(`drand round ${round} was not available`);
}

const handle = `{ consumer: ${consumer.address().to_string()}, tag: ${TAG}field }`;
const limbsLiteral = (sig: string) => `[${signatureToLimbs(sig).map((l) => `${l}u128`).join(", ")}]`;

describe("drand_relay.aleo on a local devnet", () => {
  let round = 0n;
  let requestId = 0n;
  let signature = "";

  beforeAll(async () => {
    getOrInitConsensusVersionTestHeights(TEST_HEIGHTS);
    const deployed = await client.getProgram(PROGRAM).then(
      () => true,
      () => false,
    );
    if (!deployed) {
      const txId = await manager.deploy(readFileSync(BYTECODE, "utf8"), 0, false, undefined, undefined, admin.privateKey());
      expect((await confirmed(txId)).status).toBe("accepted");
    }
  });

  it("admin configures relayer, payee, and fee, then unpauses", async () => {
    expect((await exec(admin, "set_relayer", [relayer.address().to_string()])).status).toBe("accepted");
    expect((await exec(admin, "set_relayer_payee", [payee.address().to_string()])).status).toBe("accepted");
    expect((await exec(admin, "set_fee", [`${FEE}u64`])).status).toBe("accepted");
    expect((await exec(admin, "set_paused", ["false"])).status).toBe("accepted");
    expect(await mapping("relayer", "0u8")).toBe(relayer.address().to_string());
  });

  it("request escrows the fee and binds a round at least 30 s after its block", async () => {
    const { status, blockTimestamp } = await exec(consumer, "request", [`${TAG}field`, `${FEE}u64`]);
    expect(status).toBe("accepted");
    const req = await mapping("requests", handle);
    expect(req).not.toBeNull();
    round = BigInt(/round:\s*(\d+)u64/.exec(req!)![1]);
    requestId = BigInt(/request_id:\s*(\d+)u64/.exec(req!)![1]);
    expect(req).toMatch(/status:\s*0u8/);
    expect(roundTime(round)).toBeGreaterThanOrEqual(blockTimestamp + QUICKNET.minLead);
    expect(roundTime(round)).toBeLessThan(blockTimestamp + QUICKNET.minLead + QUICKNET.period);
    expect(await mapping("results", handle)).toBeNull();
  });

  it("the same tag is rejected on-chain", async () => {
    expect((await exec(consumer, "request", [`${TAG}field`, `${FEE}u64`])).status).toBe("rejected");
  });

  it("fetches the real drand round once it is published", async () => {
    signature = await drandRound(round);
  });

  it("rejects a fulfill from anyone but the relayer", async () => {
    const r = await exec(outsider, "fulfill", [handle, `${round}u64`, limbsLiteral(signature), payee.address().to_string(), `${FEE}u64`]);
    expect(r.status).toBe("rejected");
  });

  it("rejects a mismatched round", async () => {
    const r = await exec(relayer, "fulfill", [handle, `${round + 1n}u64`, limbsLiteral(signature), payee.address().to_string(), `${FEE}u64`]);
    expect(r.status).toBe("rejected");
  });

  it("rejects a payee other than the configured one", async () => {
    const r = await exec(relayer, "fulfill", [handle, `${round}u64`, limbsLiteral(signature), relayer.address().to_string(), `${FEE}u64`]);
    expect(r.status).toBe("rejected");
  });

  it("rejects a fee other than the stored one", async () => {
    const r = await exec(relayer, "fulfill", [handle, `${round}u64`, limbsLiteral(signature), payee.address().to_string(), `${FEE - 1n}u64`]);
    expect(r.status).toBe("rejected");
  });

  it("fulfills while paused, stores output and signature, and pays the payee", async () => {
    // Pause blocks request only.
    expect((await exec(admin, "set_paused", ["true"])).status).toBe("accepted");
    expect(await balance(payee.address().to_string())).toBe(0n);

    const r = await exec(relayer, "fulfill", [handle, `${round}u64`, limbsLiteral(signature), payee.address().to_string(), `${FEE}u64`]);
    expect(r.status).toBe("accepted");

    const expected = computeOutput({
      requestId,
      consumer: consumer.address().to_string(),
      tag: TAG,
      round,
      signature,
    });
    expect(await mapping("results", handle)).toBe(expected);
    const stored = await mapping("signatures", handle);
    expect(stored!.replace(/\s+/g, "")).toBe(limbsLiteral(signature).replace(/\s+/g, ""));
    expect(await mapping("requests", handle)).toMatch(/status:\s*1u8/);
    expect(await balance(payee.address().to_string())).toBe(FEE);
  });

  it("rejects a second fulfill of the same request", async () => {
    const r = await exec(relayer, "fulfill", [handle, `${round}u64`, limbsLiteral(signature), payee.address().to_string(), `${FEE}u64`]);
    expect(r.status).toBe("rejected");
    expect(await balance(payee.address().to_string())).toBe(FEE);
  });

  it("pause blocks new requests", async () => {
    expect((await exec(consumer, "request", [`${TAG + 1n}field`, `${FEE}u64`])).status).toBe("rejected");
    expect((await exec(admin, "set_paused", ["false"])).status).toBe("accepted");
  });
});

