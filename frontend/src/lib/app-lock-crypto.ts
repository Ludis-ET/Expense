/**
 * Client-side app lock   PIN hashing (PBKDF2) + WebAuthn platform biometrics.
 * All secrets stay on-device; nothing is sent to the API.
 */

const STORAGE_KEY = "santim-app-lock";
const UNLOCKED_SESSION_KEY = "santim-app-lock-unlocked";

export type AutoLockMinutes = 0 | 1 | 2 | 5 | 15;

export interface AppLockConfig {
  enabled: boolean;
  /** PBKDF2 salt (base64) */
  salt: string;
  /** PBKDF2 hash of PIN (base64) */
  pinHash: string;
  /** Digit count chosen at setup (4–8)   used to auto-submit on unlock. */
  pinLength: number;
  /** WebAuthn credential id (base64url), if enrolled */
  credentialId?: string | null;
  /** Minutes of inactivity before re-lock. 0 = only on leave / cold start. */
  autoLockMinutes: AutoLockMinutes;
  /** Lock when the tab/app is hidden (switch apps, minimize). */
  lockOnBlur: boolean;
  updatedAt: string;
}

const PBKDF2_ITERATIONS = 120_000;

function toBase64(buf: ArrayBuffer | ArrayBufferView): string {
  const bytes = ArrayBuffer.isView(buf)
    ? new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)
    : new Uint8Array(buf);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function fromBase64(s: string): Uint8Array<ArrayBuffer> {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function toBase64Url(buf: ArrayBuffer | ArrayBufferView): string {
  return toBase64(buf).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64Url(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  return fromBase64(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
}

function randomBytes(length: number): Uint8Array<ArrayBuffer> {
  return crypto.getRandomValues(new Uint8Array(length));
}

export function loadLockConfig(): AppLockConfig | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as AppLockConfig;
    if (!parsed.pinLength) parsed.pinLength = 4;
    return parsed;
  } catch {
    return null;
  }
}

export function saveLockConfig(config: AppLockConfig): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
}

export function clearLockConfig(): void {
  localStorage.removeItem(STORAGE_KEY);
  sessionStorage.removeItem(UNLOCKED_SESSION_KEY);
}

/** Session flag   survives soft navigations, cleared on tab close / logout. */
export function markSessionUnlocked(): void {
  sessionStorage.setItem(UNLOCKED_SESSION_KEY, "1");
}

export function clearSessionUnlocked(): void {
  sessionStorage.removeItem(UNLOCKED_SESSION_KEY);
}

export function isSessionUnlocked(): boolean {
  return sessionStorage.getItem(UNLOCKED_SESSION_KEY) === "1";
}

export async function hashPin(
  pin: string,
  saltB64?: string,
): Promise<{ salt: string; hash: string }> {
  const salt = saltB64 ? fromBase64(saltB64) : randomBytes(16);
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pin),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: PBKDF2_ITERATIONS, hash: "SHA-256" },
    keyMaterial,
    256,
  );
  return { salt: toBase64(salt), hash: toBase64(bits) };
}

export async function verifyPin(
  pin: string,
  config: AppLockConfig,
): Promise<boolean> {
  const { hash } = await hashPin(pin, config.salt);
  return hash === config.pinHash;
}

export function isWebAuthnAvailable(): boolean {
  if (typeof window === "undefined") return false;
  return (
    !!window.PublicKeyCredential &&
    typeof navigator.credentials?.create === "function"
  );
}

export async function isPlatformAuthenticatorAvailable(): Promise<boolean> {
  if (!isWebAuthnAvailable()) return false;
  try {
    return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
  } catch {
    return false;
  }
}

function rpId(): string {
  return window.location.hostname;
}

function userIdFromEmail(email: string): Uint8Array<ArrayBuffer> {
  const enc = new TextEncoder().encode(email.slice(0, 64));
  const out = new Uint8Array(32);
  out.set(enc.subarray(0, Math.min(enc.length, 32)));
  return out;
}

/** Enroll Face ID / Touch ID / Windows Hello / Android biometrics. */
export async function enrollBiometric(user: {
  id: string;
  email: string;
  name: string;
}): Promise<string> {
  if (!isWebAuthnAvailable())
    throw new Error("Biometrics are not supported in this browser");

  const challenge = randomBytes(32);
  const credential = (await navigator.credentials.create({
    publicKey: {
      challenge,
      rp: { name: "Santim", id: rpId() },
      user: {
        id: userIdFromEmail(user.email || user.id),
        name: user.email,
        displayName: user.name || user.email,
      },
      pubKeyCredParams: [
        { type: "public-key", alg: -7 }, // ES256
        { type: "public-key", alg: -257 }, // RS256
      ],
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        userVerification: "required",
        residentKey: "preferred",
      },
      timeout: 60_000,
      attestation: "none",
    },
  })) as PublicKeyCredential | null;

  if (!credential) throw new Error("Biometric setup was cancelled");
  return toBase64Url(credential.rawId);
}

/** Prompt platform authenticator to unlock. */
export async function unlockWithBiometric(
  credentialId: string,
): Promise<boolean> {
  if (!isWebAuthnAvailable()) return false;
  try {
    const challenge = randomBytes(32);
    const assertion = await navigator.credentials.get({
      publicKey: {
        challenge,
        rpId: rpId(),
        allowCredentials: [
          {
            type: "public-key",
            id: fromBase64Url(credentialId),
            transports: ["internal"],
          },
        ],
        userVerification: "required",
        timeout: 60_000,
      },
    });
    return !!assertion;
  } catch {
    return false;
  }
}

export function validatePin(pin: string): string | null {
  if (!/^\d{4,8}$/.test(pin)) return "Use a 4–8 digit PIN";
  if (/^(\d)\1+$/.test(pin)) return "Avoid a PIN of all identical digits";
  if (["1234", "0000", "1111", "2222", "4321", "1212", "2580"].includes(pin)) {
    return "Choose a less obvious PIN";
  }
  return null;
}
