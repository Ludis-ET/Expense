import { describe, expect, it } from 'vitest';
import {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
} from '../src/modules/auth/jwt.js';
import type { AuthUser } from '../src/core/context.js';

const user: AuthUser = { id: 'u1', email: 'a@b.com' };

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

  it('rejects an access token used as a refresh token', () => {
    const access = signAccessToken(user);
    expect(() => verifyRefreshToken(access)).toThrow();
  });

  it('rejects a tampered token', () => {
    const token = signAccessToken(user);
    expect(() => verifyAccessToken(token + 'x')).toThrow();
  });
});
