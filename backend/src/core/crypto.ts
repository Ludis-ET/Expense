import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from 'node:crypto';
import { env } from '../config/env.js';

// Derive a stable 32-byte key. Prefer a dedicated AI_ENCRYPTION_KEY; otherwise
// derive deterministically from JWT_SECRET so the app works out of the box.
// In production, set AI_ENCRYPTION_KEY explicitly and rotate independently.
const KEY = scryptSync(env.AI_ENCRYPTION_KEY ?? env.JWT_SECRET, 'santim.ai.kdf', 32);

/** Encrypt a secret → "iv:tag:ciphertext" (all base64url). */
export function encryptSecret(plaintext: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', KEY, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, ciphertext].map((b) => b.toString('base64url')).join(':');
}

/** Decrypt a value produced by encryptSecret. Returns null if malformed/tampered. */
export function decryptSecret(payload: string): string | null {
  try {
    const [ivB64, tagB64, dataB64] = payload.split(':');
    if (!ivB64 || !tagB64 || !dataB64) return null;
    const decipher = createDecipheriv('aes-256-gcm', KEY, Buffer.from(ivB64, 'base64url'));
    decipher.setAuthTag(Buffer.from(tagB64, 'base64url'));
    const plaintext = Buffer.concat([decipher.update(Buffer.from(dataB64, 'base64url')), decipher.final()]);
    return plaintext.toString('utf8');
  } catch {
    return null;
  }
}
