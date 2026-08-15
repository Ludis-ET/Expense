import jwt from 'jsonwebtoken';
import { describe, expect, it } from 'vitest';
import {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
} from '../src/modules/auth/jwt.js';
import { env } from '../src/config/env.js';
import type { AuthUser } from '../src/core/context.js';

const user: AuthUser = { id: 'u1', email: 'a@b.com' };

describe('jwt', () => {
  it('round-trips an access token', () => {
    const token = signAccessToken(user);
    expect(verifyAccessToken(token)).toEqual(user);
  });

  it('round-trips a refresh token, carrying its version', () => {
    const token = signRefreshToken(user.id, 3);
    expect(verifyRefreshToken(token)).toEqual({ userId: user.id, tokenVersion: 3 });
  });

  it('reports the version so a stale token can be refused', () => {
    // What `refresh()` compares against `User.tokenVersion`: a token minted
    // before a sign-out carries the old number and no longer matches.
    const beforeSignOut = signRefreshToken(user.id, 1);
    const afterSignOut = signRefreshToken(user.id, 2);
    expect(verifyRefreshToken(beforeSignOut).tokenVersion).toBe(1);
    expect(verifyRefreshToken(afterSignOut).tokenVersion).toBe(2);
  });

  it('treats a pre-revocation token as version 0', () => {
    // Tokens issued before the version existed have no `ver` claim. They must
    // keep working until they expire, or deploying revocation would sign
    // everyone out at once.
    const legacy = jwt.sign({ sub: user.id, typ: 'refresh' }, env.JWT_SECRET, {
      expiresIn: '7d',
    });
    expect(verifyRefreshToken(legacy)).toEqual({ userId: user.id, tokenVersion: 0 });
  });

  it('rejects a refresh token used as an access token', () => {
    const refresh = signRefreshToken(user.id, 0);
    expect(() => verifyAccessToken(refresh)).toThrow();
  });

  it('rejects an access token used as a refresh token', () => {
    const access = signAccessToken(user);
    expect(() => verifyRefreshToken(access)).toThrow();
  });

  it('rejects a token whose version was tampered with', () => {
    // Re-signing with a different secret must not pass, so a client cannot
    // simply bump its own `ver` to survive a sign-out.
    const forged = jwt.sign({ sub: user.id, typ: 'refresh', ver: 99 }, 'not-the-secret');
    expect(() => verifyRefreshToken(forged)).toThrow();
  });

  it('rejects a tampered token', () => {
    const token = signAccessToken(user);
    expect(() => verifyAccessToken(token + 'x')).toThrow();
  });
});
