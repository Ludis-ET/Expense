import { Prisma } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import {
  availableOf,
  heldOf,
  loadSnapshot,
  realOf,
  readyToAssign,
  splitPair,
  withMoneyLock,
  ZERO,
  type LedgerSnapshot,
  type Money,
} from '../../core/money/index.js';
import { assertSound } from '../../core/money/postings.js';
import type { CreateAccountInput, UpdateAccountInput } from './accounts.schema.js';

async function assertOwnedAccount(id: string, userId: string) {
  const account = await prisma.account.findFirst({ where: { id, userId } });
  if (!account) throw new NotFoundError('Account not found');
  return account;
}

/**
 * All wallets with their money.
 *
 * `realBalance` is what is physically there. `lockedAmount` is the slice plans
 * have reserved. `balance` is what is left - the figure every "can I spend this"
 * surface uses. All three come from the money core, so they cannot disagree with
 * the budgets page, the dashboard, or each other.
 */
export async function list(user: AuthUser) {
  const [accounts, snap] = await Promise.all([
    prisma.account.findMany({
      where: { userId: user.id },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
    }),
    loadSnapshot(user.id),
  ]);

  const rows = accounts.map((a) => ({
    ...a,
    openingBalance: a.openingBalance.toFixed(2),
    realBalance: realOf(snap, a.id).toFixed(2),
    lockedAmount: heldOf(snap, a.id).toFixed(2),
    balance: availableOf(snap, a.id).toFixed(2),
    reportedBalance: a.reportedBalance ? a.reportedBalance.toFixed(2) : null,
    reportedAt: a.reportedAt ? a.reportedAt.toISOString() : null,
    /**
     * How far Santim's figure is from what the bank last said. Positive means
     * Santim thinks you have more than the bank does - usually spending that was
     * never recorded.
     */
    drift:
      a.reportedBalance !== null
        ? realOf(snap, a.id).sub(a.reportedBalance).toFixed(2)
        : null,
  }));

  return { items: rows };
}

/** What one wallet is holding, and for which plans. Drives the wallet sheet. */
export async function reservations(user: AuthUser, accountId: string) {
  await assertOwnedAccount(accountId, user.id);
  const snap = await loadSnapshot(user.id);

  const rows: Array<{ budgetId: string; amount: Money }> = [];
  for (const [key, amount] of snap.held) {
    // Keys are `${accountId}\0${budgetId}` — never split on space.
    const { accountId: heldAccountId, budgetId } = splitPair(key);
    if (heldAccountId === accountId && amount.gt(0)) rows.push({ budgetId, amount });
  }
  if (rows.length === 0) return { items: [] };

  const budgets = await prisma.budget.findMany({
    // The ids come from this user's own snapshot, so `userId` is redundant
    // today. It is here so the guarantee is local to the query rather than an
    // assumption about every future caller.
    where: { userId: user.id, id: { in: rows.map((r) => r.budgetId) } },
    select: { id: true, name: true, icon: true, color: true, currency: true, state: true },
  });
  const byId = new Map(budgets.map((b) => [b.id, b]));

  return {
    items: rows
      .filter((r) => byId.has(r.budgetId))
      .sort((a, b) => b.amount.comparedTo(a.amount))
      .map((r) => ({ plan: byId.get(r.budgetId)!, amount: r.amount.toFixed(2) })),
  };
}

// ---------------------------------------------------------------------------
// Figures other modules ask for
// ---------------------------------------------------------------------------

export async function accountBalance(
  userId: string,
  accountId: string,
  excludeTxId?: string,
): Promise<Prisma.Decimal> {
  const snap = await loadSnapshot(userId, excludeTxId ? { excludeTxId } : {});
  if (!snap.real.has(accountId)) throw new NotFoundError('Account not found');
  return realOf(snap, accountId);
}

export async function availableBalance(
  userId: string,
  accountId: string,
  excludeTxId?: string,
): Promise<Prisma.Decimal> {
  const snap = await loadSnapshot(userId, excludeTxId ? { excludeTxId } : {});
  if (!snap.real.has(accountId)) throw new NotFoundError('Account not found');
  return availableOf(snap, accountId);
}

/** Money genuinely free to spend in one currency - "ready to assign". */
export async function availableTotal(userId: string, currency: string): Promise<Prisma.Decimal> {
  return readyToAssign(await loadSnapshot(userId), currency);
}

export async function snapshotFor(userId: string): Promise<LedgerSnapshot> {
  return loadSnapshot(userId);
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

export async function create(user: AuthUser, input: CreateAccountInput) {
  if (input.isDefault) {
    await prisma.account.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
  }
  return prisma.account.create({ data: { ...input, userId: user.id } });
}

/**
 * Editing a wallet.
 *
 * Two fields are money, not settings. Lowering an opening balance can leave
 * plans reserving money the wallet no longer holds, and changing the currency
 * would reinterpret every past movement as a different denomination. Both are
 * checked here, and the invariant proof catches anything these messages miss.
 */
export async function update(user: AuthUser, id: string, input: UpdateAccountInput) {
  const existing = await assertOwnedAccount(id, user.id);

  if (input.currency && input.currency.toUpperCase() !== existing.currency) {
    const movements = await prisma.transaction.count({
      where: { OR: [{ accountId: id }, { transferAccountId: id }] },
    });
    const held = await prisma.budgetAllocation.count({ where: { accountId: id } });
    if (movements > 0 || held > 0) {
      throw new ConflictError(
        `"${existing.name}" already holds ${existing.currency} movements. Changing its currency now would reinterpret every one of them. Create a ${input.currency.toUpperCase()} wallet and transfer across instead.`,
      );
    }
  }

  return withMoneyLock(user.id, async (tx) => {
    if (input.isDefault) {
      await tx.account.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
    }

    if (input.archived === true && existing.archived === false) {
      const snap = await loadSnapshot(user.id, {}, tx);
      const locked = heldOf(snap, id);
      if (locked.gt(0)) {
        throw new ConflictError(
          `"${existing.name}" is holding ${locked.toFixed(2)} ${existing.currency} for budget plans. Give that back, or move it to another wallet, before archiving.`,
        );
      }
    }

    const account = await tx.account.update({ where: { id }, data: input });

    if (input.openingBalance !== undefined || input.currency !== undefined) {
      await assertSound(
        tx,
        user.id,
        `That change to "${existing.name}" would not add up:`,
      );
    }
    return account;
  });
}

export async function remove(user: AuthUser, id: string) {
  const account = await assertOwnedAccount(id, user.id);

  return withMoneyLock(user.id, async (tx) => {
    const snap = await loadSnapshot(user.id, {}, tx);
    const locked = heldOf(snap, id);
    if (locked.gt(0)) {
      const planCount = [...snap.held.keys()].filter((k) => k.startsWith(`${id} `)).length;
      throw new ConflictError(
        `"${account.name}" is holding ${locked.toFixed(2)} ${account.currency} for ${planCount === 1 ? 'a budget plan' : `${planCount} budget plans`}. Give it back first.`,
      );
    }

    const txCount = await tx.transaction.count({
      where: { OR: [{ accountId: id }, { transferAccountId: id }, { budgetSourceAccountId: id }] },
    });
    if (txCount > 0) {
      throw new ConflictError('This wallet has transactions. Archive it instead of deleting.');
    }

    // Give-backs are not holdings. Counting them is why a wallet that had ever
    // funded a plan could never be deleted, even after everything came back.
    await tx.budgetAllocation.deleteMany({ where: { accountId: id, userId: user.id } });
    await tx.account.delete({ where: { id } });
  });
}

/**
 * Record what the bank itself says this wallet holds, read out of a parsed
 * message. Kept beside Santim's own figure so drift is visible instead of
 * silently accumulating.
 */
export async function recordReportedBalance(
  userId: string,
  accountId: string,
  balance: Prisma.Decimal,
  at: Date,
): Promise<void> {
  const account = await prisma.account.findFirst({ where: { id: accountId, userId } });
  if (!account) return;
  // Only move forward: an old message arriving late must not overwrite a newer
  // reading with a staler one.
  if (account.reportedAt && account.reportedAt > at) return;
  await prisma.account.update({
    where: { id: accountId },
    data: { reportedBalance: balance, reportedAt: at },
  });
}

/**
 * Wallets whose recorded balance has drifted from what the bank last reported.
 * The SMS pipeline already reads these figures out of every message; until now
 * it threw them away.
 */
export async function driftReport(user: AuthUser) {
  const [accounts, snap] = await Promise.all([
    prisma.account.findMany({
      where: { userId: user.id, archived: false, reportedBalance: { not: null } },
      select: {
        id: true,
        name: true,
        currency: true,
        icon: true,
        color: true,
        reportedBalance: true,
        reportedAt: true,
      },
    }),
    loadSnapshot(user.id),
  ]);

  const items = accounts
    .map((a) => {
      const ours = realOf(snap, a.id);
      const theirs = a.reportedBalance ?? ZERO;
      const difference = ours.sub(theirs);
      return {
        account: { id: a.id, name: a.name, currency: a.currency, icon: a.icon, color: a.color },
        santimBalance: ours.toFixed(2),
        bankBalance: theirs.toFixed(2),
        difference: difference.toFixed(2),
        reportedAt: a.reportedAt ? a.reportedAt.toISOString() : null,
        /** More in Santim than the bank means spending that was never recorded. */
        direction: difference.gt(0) ? ('missing-spending' as const) : ('missing-income' as const),
      };
    })
    // A few cents of rounding is not worth a card on someone's dashboard.
    .filter((row) => Math.abs(Number(row.difference)) >= 1)
    .sort((a, b) => Math.abs(Number(b.difference)) - Math.abs(Number(a.difference)));

  return { items };
}

/**
 * Bring a wallet in line with the bank by recording the difference as a real
 * movement, so the books stay explainable rather than being quietly overwritten.
 */
export async function settleDrift(
  user: AuthUser,
  accountId: string,
  categoryId: string,
): Promise<{ adjusted: string } | null> {
  const account = await assertOwnedAccount(accountId, user.id);
  if (account.reportedBalance === null) {
    throw new BadRequestError('No bank balance has been captured for this wallet yet.');
  }

  const snap = await loadSnapshot(user.id);
  const difference = realOf(snap, accountId).sub(account.reportedBalance);
  if (difference.isZero()) return null;

  const { postTransaction } = await import('../../core/money/postings.js');
  const missingSpending = difference.gt(0);

  await postTransaction(user.id, {
    kind: missingSpending ? 'EXPENSE' : 'INCOME',
    amount: difference.abs(),
    currency: account.currency,
    date: account.reportedAt ?? new Date(),
    accountId,
    categoryId,
    note: `Matched to the balance ${account.name} reported`,
    tags: ['reconciled'],
  });

  return { adjusted: difference.abs().toFixed(2) };
}
