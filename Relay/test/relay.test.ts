import { describe, expect, it } from "vitest";
import { payload } from "../src/apns";
import { handle, type Env, type Sender } from "../src/index";
import { base64Encode, open, seal, type Device } from "../src/seal";

const secret = base64Encode(new Uint8Array(32).fill(7));
const token = "ab".repeat(32);

function env(allow = true): Env {
  return {
    APNS_KEY: "", APNS_KEY_ID: "", APNS_TEAM_ID: "", APNS_TOPIC: "com.example.woot",
    RELAY_SECRET: secret,
    PUSH_LIMIT: { limit: async () => ({ success: allow }) },
  };
}

function recorder(result: Awaited<ReturnType<Sender>>) {
  const sent: { message: Uint8Array; device: Device; expiresAt: number }[] = [];
  const send: Sender = async (message, device, expiresAt) => {
    sent.push({ message, device, expiresAt });
    return result;
  };
  return { sent, send };
}

const post = (path: string, body: BodyInit, headers: Record<string, string> = {}) =>
  new Request(`https://push.example.com${path}`, { method: "POST", body, headers });

describe("relay", () => {
  it("seals devices so only the relay can read or forge them", async () => {
    const device: Device = { token, environment: "development" };
    const sealed = await seal(device, secret);
    expect(await open(sealed, secret)).toEqual(device);
    expect(sealed).not.toContain(token);
    expect(await open(sealed.slice(0, -2) + (sealed.endsWith("AA") ? "BB" : "AA"), secret)).toBeNull();
    expect(await open(sealed, base64Encode(new Uint8Array(32).fill(8)))).toBeNull();
  });

  it("registers a device and forwards its pushes", async () => {
    const { sent, send } = recorder("delivered");
    const registration = await handle(post("/v1/devices", JSON.stringify({ token: token.toUpperCase(), environment: "production" })), env(), send);
    expect(registration.status).toBe(200);
    const { endpoint } = (await registration.json()) as { endpoint: string };
    expect(new URL(endpoint).origin).toBe("https://push.example.com");

    const response = await handle(post(new URL(endpoint).pathname, "ciphertext", { TTL: "60" }), env(), send);
    expect(response.status).toBe(201);
    expect(new TextDecoder().decode(sent[0].message)).toBe("ciphertext");
    expect(sent[0].device).toEqual({ token, environment: "production" });
    expect(sent[0].expiresAt - Date.now() / 1000).toBeCloseTo(60, -1);
  });

  it("tells Chatwoot when a device is gone or APNs refuses", async () => {
    const path = `/v1/push/${await seal({ token, environment: "production" }, secret)}`;
    expect((await handle(post(path, "x"), env(), recorder("gone").send)).status).toBe(410);
    expect((await handle(post(path, "x"), env(), recorder({ failed: "TooManyRequests" }).send)).status).toBe(502);
  });

  it("rejects bad input without calling APNs", async () => {
    const { sent, send } = recorder("delivered");
    const path = `/v1/push/${await seal({ token, environment: "production" }, secret)}`;
    expect((await handle(post("/v1/devices", JSON.stringify({ token: "nothex", environment: "production" })), env(), send)).status).toBe(400);
    expect((await handle(post("/v1/devices", "not json"), env(), send)).status).toBe(400);
    expect((await handle(post("/v1/push/forged", "x"), env(), send)).status).toBe(404);
    expect((await handle(post(path, new Uint8Array(5000)), env(), send)).status).toBe(413);
    expect((await handle(post(path, "x"), env(false), send)).status).toBe(429);
    expect((await handle(new Request("https://push.example.com/health"), env(), send)).status).toBe(200);
    expect(sent).toHaveLength(0);
  });

  it("asks the app's extension to decrypt", () => {
    const body = JSON.parse(payload(new TextEncoder().encode("secret")));
    expect(body.aps["mutable-content"]).toBe(1);
    expect(atob(body.m)).toBe("secret");
  });
});
