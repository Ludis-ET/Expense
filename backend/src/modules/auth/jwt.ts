import jwt, { type SignOptions } from 'jsonwebtoken';
import { env } from '../../config/env.js';
import type { AuthUser } from '../../core/context.js';

type AccessPayload = AuthUser & { typ: 'access' };
type RefreshPayload = { sub: string; typ: 'refresh' };

export function signAccessToken(user: AuthUser): string {
  const payload: AccessPayload = { ...user, typ: 'access' };
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN } as SignOptions);
}

export function signRefreshToken(userId: string): string {
  const payload: RefreshPayload = { sub: userId, typ: 'refresh' };
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_REFRESH_EXPIRES_IN } as SignOptions);
}

export function verifyAccessToken(token: string): AuthUser {
  const decoded = jwt.verify(token, env.JWT_SECRET) as AccessPayload;
  if (decoded.typ !== 'access') throw new Error('Not an access token');
  return { id: decoded.id, email: decoded.email, role: decoded.role, orgId: decoded.orgId };
}

export function verifyRefreshToken(token: string): { userId: string } {
  const decoded = jwt.verify(token, env.JWT_SECRET) as RefreshPayload;
  if (decoded.typ !== 'refresh') throw new Error('Not a refresh token');
  return { userId: decoded.sub };
}
