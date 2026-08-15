import bcrypt from 'bcryptjs';
import { AccountType } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { ConflictError, UnauthorizedError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { DEFAULT_CATEGORIES } from '../categories/default-categories.js';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from './jwt.js';
import type { LoginInput, RegisterInput } from './auth.schema.js';
import { randomAvatarId, randomBannerId } from '../users/profile-presets.js';

const BCRYPT_ROUNDS = 12;

/**
 * A real hash of a value nobody can supply, compared against when the email is
 * unknown.
 *
 * Returning early on a missing user made login a timing oracle: a hit cost 12
 * rounds of bcrypt, a miss cost one indexed lookup, and the gap was wide enough
 * to enumerate an address list with. Both paths now do the same work.
 */
const DUMMY_HASH = bcrypt.hashSync('santim.timing.equaliser', BCRYPT_ROUNDS);

function toAuthUser(u: { id: string; email: string }): AuthUser {
  return { id: u.id, email: u.email };
}

function issueTokens(user: AuthUser, tokenVersion: number) {
  return {
    user,
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user.id, tokenVersion),
  };
}

export async function register(input: RegisterInput) {
  const existing = await prisma.user.findUnique({ where: { email: input.email } });
  if (existing) throw new ConflictError('Email is already registered');

  const passwordHash = await bcrypt.hash(input.password, BCRYPT_ROUNDS);

  // New users start with the default category set and a Cash account so the
  // app is usable immediately after signup.
  const user = await prisma.$transaction(async (tx) => {
    const created = await tx.user.create({
      data: {
        name: input.name,
        email: input.email,
        passwordHash,
        locale: input.locale,
        avatarId: randomAvatarId(),
        bannerId: randomBannerId(),
      },
    });

    await tx.category.createMany({
      data: DEFAULT_CATEGORIES.map((c) => ({ ...c, userId: created.id, isDefault: true })),
    });

    await tx.account.create({
      data: {
        userId: created.id,
        name: 'Cash',
        type: AccountType.CASH,
        icon: 'banknote',
        isDefault: true,
      },
    });

    // No catch-all plan is created. Spending you never set money aside for is
    // simply an expense with no plan on it, which the budgets page presents as
    // an Unplanned card. A row that could not be funded, closed or deleted was
    // only ever a source of special cases.

    return created;
  });

  return issueTokens(toAuthUser(user), user.tokenVersion);
}

export async function login(input: LoginInput) {
  const user = await prisma.user.findUnique({ where: { email: input.email } });

  // Always compare, even when there is no user, so the two outcomes cost the
  // same. The result of the dummy comparison is discarded.
  const ok = await bcrypt.compare(input.password, user?.passwordHash ?? DUMMY_HASH);
  if (!user || !ok) throw new UnauthorizedError('Invalid email or password');

  return issueTokens(toAuthUser(user), user.tokenVersion);
}

export async function refresh(refreshToken: string) {
  let userId: string;
  let tokenVersion: number;
  try {
    ({ userId, tokenVersion } = verifyRefreshToken(refreshToken));
  } catch {
    throw new UnauthorizedError('Invalid or expired refresh token');
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new UnauthorizedError('User no longer exists');

  // The whole point of the version: a token minted before the last sign-out is
  // refused here even though its signature and expiry are both still valid.
  if (tokenVersion !== user.tokenVersion) {
    throw new UnauthorizedError('This session was signed out. Sign in again.');
  }

  return issueTokens(toAuthUser(user), user.tokenVersion);
}

/**
 * Ends every session this user holds.
 *
 * Deliberately not scoped to the calling device. Refresh tokens carry no device
 * identity, so "sign out this one phone" is not a promise this design can keep -
 * and quietly signing out only some sessions would be worse than saying plainly
 * that signing out signs you out everywhere.
 */
export async function logout(userId: string) {
  await prisma.user.update({
    where: { id: userId },
    data: { tokenVersion: { increment: 1 } },
  });
  return { signedOut: true };
}
