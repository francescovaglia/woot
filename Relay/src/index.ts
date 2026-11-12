// woot-push: hands Chatwoot's Web Push notifications to APNs.
// Chatwoot posts to /v1/push/:device; the app asks /v1/devices for that URL once it has an
// APNs token. Messages arrive encrypted to keys that only the device holds, so the relay
// forwards ciphertext it cannot read.

import { sendToAPNs, type Credentials, type Delivery } from "./apns";
import { open, seal, type Device } from "./seal";

export interface Env extends Credentials {
  /** 32 random bytes in base64. Changing it invalidates every endpoint until apps register again. */
  RELAY_SECRET: string;
  /** Caps pushes per device, so a misbehaving server can't flood a phone. */
  PUSH_LIMIT: RateLimit;
}

export type Sender = (message: Uint8Array, device: Device, expiresAt: number) => Promise<Delivery>;

// RFC 8030 caps a push message at 4096 bytes, well within APNs' payload limit once encoded.
const maxMessageSize = 4096;
const maxTTL = 7 * 24 * 3600;

export async function handle(request: Request, env: Env, send: Sender): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") return new Response("ok");

  if (request.method === "POST" && url.pathname === "/v1/devices") {
    const body = (await request.json().catch(() => null)) as { token?: unknown; environment?: unknown } | null;
    const token = typeof body?.token === "string" ? body.token.toLowerCase() : "";
    const environment = body?.environment;
    if (!/^[0-9a-f]{64,200}$/.test(token) || (environment !== "development" && environment !== "production")) {
      return new Response("Invalid device", { status: 400 });
    }
    const sealed = await seal({ token, environment }, env.RELAY_SECRET);
    // Push endpoints are always HTTPS; behind a local proxy the request itself may arrive as http.
    return Response.json({ endpoint: `https://${url.host}/v1/push/${sealed}` });
  }

  const push = url.pathname.match(/^\/v1\/push\/([A-Za-z0-9_-]+)$/);
  if (request.method === "POST" && push) {
    const device = await open(push[1], env.RELAY_SECRET);
    if (!device) return new Response(null, { status: 404 });
    if (!(await env.PUSH_LIMIT.limit({ key: device.token })).success) return new Response(null, { status: 429 });
    const message = new Uint8Array(await request.arrayBuffer());
    if (message.length > maxMessageSize) return new Response(null, { status: 413 });
    const ttl = Math.min(Math.max(Number(request.headers.get("TTL")) || 0, 0), maxTTL);

    const result = await send(message, device, Math.floor(Date.now() / 1000) + ttl);
    if (result === "delivered") return new Response(null, { status: 201 });
    // Chatwoot deletes the subscription when the push service answers 410.
    if (result === "gone") return new Response(null, { status: 410 });
    console.warn("APNs refused a push:", result.failed);
    return new Response(null, { status: 502 });
  }

  return new Response(null, { status: 404 });
}

export default {
  fetch: (request, env) => handle(request, env, (message, device, expiresAt) => sendToAPNs(env, message, device, expiresAt)),
} satisfies ExportedHandler<Env>;
