import bcrypt from 'bcryptjs';
import { AccountType, BudgetKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { ConflictError, UnauthorizedError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { DEFAULT_CATEGORIES } from '../categories/default-categories.js';
import { UNPLANNED_NAME, unplannedId } from '../budgets/budgets.service.js';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from './jwt.js';
import type { LoginInput, RegisterInput } from './auth.schema.js';

const BCRYPT_ROUNDS = 12;

function toAuthUser(u: { id: string; email: string }): AuthUser {
  return { id: u.id, email: u.email };
}

function issueTokens(user: AuthUser) {
  return {
    user,
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user.id),
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
      data: { name: input.name, email: input.email, passwordHash, locale: input.locale },
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

    // The built-in catch-all plan, so spending has somewhere to land from day
    // one. Its id is derived from the user id, keeping it unique per account.
    await tx.budget.create({
      data: {
        id: unplannedId(created.id),
        userId: created.id,
        name: UNPLANNED_NAME,
        kind: BudgetKind.UNPLANNED,
        plannedAmount: 0,
        currency: created.currency,
        icon: 'circle-ellipsis',
        color: '#64748b',
        note: 'Everything you spend without setting money aside first.',
        alertThreshold: 100,
      },
    });

    return created;
  });

  return issueTokens(toAuthUser(user));
}

export async function login(input: LoginInput) {
  const user = await prisma.user.findUnique({ where: { email: input.email } });
  if (!user) throw new UnauthorizedError('Invalid email or password');

  const ok = await bcrypt.compare(input.password, user.passwordHash);
  if (!ok) throw new UnauthorizedError('Invalid email or password');

  return issueTokens(toAuthUser(user));
}

export async function refresh(refreshToken: string) {
  let userId: string;
  try {
    ({ userId } = verifyRefreshToken(refreshToken));
  } catch {
    throw new UnauthorizedError('Invalid or expired refresh token');
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new UnauthorizedError('User no longer exists');

  return issueTokens(toAuthUser(user));
}
