import { base64Decode, base64Encode, base64URLEncode, type Device } from "./seal";

export type Delivery = "delivered" | "gone" | { failed: string };

export interface Credentials {
  APNS_KEY: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  /** The app's bundle id. */
  APNS_TOPIC: string;
}

// Apple wants the same token reused for up to an hour and refreshed at most every
// 20 minutes, so it lives as long as the isolate does, up to 50 minutes.
let cached: { keyID: string; token: string; issuedAt: number } | undefined;

async function authenticationToken(credentials: Credentials): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.keyID === credentials.APNS_KEY_ID && now - cached.issuedAt < 50 * 60) return cached.token;
  const pem = credentials.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", base64Decode(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encode = (value: object) => base64URLEncode(new TextEncoder().encode(JSON.stringify(value)));
  const input = `${encode({ alg: "ES256", kid: credentials.APNS_KEY_ID })}.${encode({ iss: credentials.APNS_TEAM_ID, iat: now })}`;
  // WebCrypto returns ECDSA signatures as raw r || s, which is what JWT expects.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  cached = { keyID: credentials.APNS_KEY_ID, token: `${input}.${base64URLEncode(new Uint8Array(signature))}`, issuedAt: now };
  return cached.token;
}

/** The visible text is only a fallback: the app's notification extension decrypts `m`
 *  and replaces it with the contact's name and message. */
export function payload(message: Uint8Array): string {
  return JSON.stringify({
    aps: { alert: { title: "Woot", body: "New notification" }, sound: "default", "mutable-content": 1 },
    m: base64Encode(message),
  });
}

export async function sendToAPNs(credentials: Credentials, message: Uint8Array, device: Device, expiresAt: number): Promise<Delivery> {
  const host = device.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  try {
    const response = await fetch(`https://${host}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await authenticationToken(credentials)}`,
        "apns-topic": credentials.APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(expiresAt),
      },
      body: payload(message),
    });
    if (response.ok) return "delivered";
    const reason = ((await response.json().catch(() => ({}))) as { reason?: string }).reason ?? String(response.status);
    return response.status === 410 || reason === "BadDeviceToken" ? "gone" : { failed: reason };
  } catch (error) {
    return { failed: String(error) };
  }
}
