import jwt, { type SignOptions } from 'jsonwebtoken';
import { env } from '../../config/env.js';
import type { AuthUser } from '../../core/context.js';

type AccessPayload = AuthUser & { typ: 'access' };

/**
 * `ver` mirrors `User.tokenVersion` at the moment the token was issued.
 *
 * A stateless refresh token cannot be taken back, which meant signing out did
 * nothing a thief would notice. Carrying the version makes revocation a single
 * integer comparison at refresh time - no denylist to store, no sweep to run.
 */
type RefreshPayload = { sub: string; typ: 'refresh'; ver: number };

export function signAccessToken(user: AuthUser): string {
  const payload: AccessPayload = { ...user, typ: 'access' };
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN } as SignOptions);
}

export function signRefreshToken(userId: string, tokenVersion: number): string {
  const payload: RefreshPayload = { sub: userId, typ: 'refresh', ver: tokenVersion };
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_REFRESH_EXPIRES_IN } as SignOptions);
}

export function verifyAccessToken(token: string): AuthUser {
  const decoded = jwt.verify(token, env.JWT_SECRET) as AccessPayload;
  if (decoded.typ !== 'access') throw new Error('Not an access token');
  return { id: decoded.id, email: decoded.email };
}

export function verifyRefreshToken(token: string): { userId: string; tokenVersion: number } {
  const decoded = jwt.verify(token, env.JWT_SECRET) as RefreshPayload;
  if (decoded.typ !== 'refresh') throw new Error('Not a refresh token');
  // Tokens minted before revocation existed carry no `ver`. Treating them as
  // version 0 lets them keep working until they expire, which is what makes
  // this deployable without signing everyone out.
  return { userId: decoded.sub, tokenVersion: decoded.ver ?? 0 };
}
