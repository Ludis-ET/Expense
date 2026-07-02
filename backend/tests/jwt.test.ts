import { describe, expect, it } from 'vitest';
import { Role } from '@prisma/client';
import {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
} from '../src/modules/auth/jwt.js';
import type { AuthUser } from '../src/core/context.js';

const user: AuthUser = { id: 'u1', email: 'a@b.com', role: Role.ADMIN, orgId: 'org1' };

describe('jwt', () => {
  it('round-trips an access token', () => {
    const token = signAccessToken(user);
    expect(verifyAccessToken(token)).toEqual(user);
  });

  it('round-trips a refresh token', () => {
    const token = signRefreshToken(user.id);
    expect(verifyRefreshToken(token)).toEqual({ userId: user.id });
  });

  it('rejects a refresh token used as an access token', () => {
    const refresh = signRefreshToken(user.id);
    expect(() => verifyAccessToken(refresh)).toThrow();
  });

  it('rejects a tampered token', () => {
    const token = signAccessToken(user);
    expect(() => verifyAccessToken(token + 'x')).toThrow();
  });
});
