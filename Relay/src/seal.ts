// Turns a device into an opaque, unforgeable path component. The relay keeps no
// storage: everything it needs to deliver a push travels inside the endpoint URL,
// and only the relay can read or mint one.

export type Environment = "development" | "production";

export interface Device {
  token: string;
  environment: Environment;
}

async function key(secret: string): Promise<CryptoKey> {
  const raw = base64Decode(secret);
  if (raw.length !== 32) throw new Error("RELAY_SECRET must be 32 random bytes in base64");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function seal(device: Device, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(`${device.environment}:${device.token}`);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await key(secret), plain));
  return base64URLEncode(concat(iv, sealed));
}

export async function open(sealed: string, secret: string): Promise<Device | null> {
  try {
    const data = base64URLDecode(sealed);
    const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: data.slice(0, 12) }, await key(secret), data.slice(12));
    const [environment, token] = new TextDecoder().decode(plain).split(":");
    if ((environment !== "development" && environment !== "production") || !token) return null;
    return { environment, token };
  } catch {
    return null;
  }
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function base64Decode(text: string): Uint8Array {
  return Uint8Array.from(atob(text), (char) => char.charCodeAt(0));
}

export function base64URLEncode(bytes: Uint8Array): string {
  return base64Encode(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64URLDecode(text: string): Uint8Array {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  return base64Decode(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
}
