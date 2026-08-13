/**
 * Recent movements, and undoing them.
 *
 * Everything that moves money - a transaction, a fill-up, a give-back, a move
 * between plans, a raise or a cut - lands in one feed here, newest first. That
 * feed is the answer to "what did I just do?", and the place to take it back.
 *
 * Undo *removes* the movement. It does not post a mirror-image entry that leaves
 * two rows where there was one: a mistake should leave no trace, the way it does
 * when you cross a line out of a paper ledger rather than writing it again
 * backwards. Every undo runs through the money core, so the books are re-proved
 * afterwards; anything that would leave them unbalanced - undoing the fill-up
 * whose money has since been spent - is refused with the reason.
 */
import { BudgetAllocationKind, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import {
  assertSound,
  availableOf,
  deleteTransaction,
  heldOf,
  loadSnapshot,
  potOf,
  readyToAssign,
  realOf,
  withMoneyLock,
  ZERO,
} from '../../core/money/index.js';
import { inspect, repair } from '../../core/money/reconcile.js';

/**
 * How long a movement stays undoable.
 *
 * Long enough to catch the mistake you notice tomorrow morning, short enough
 * that undo never becomes a way of rewriting last month. Older movements are
 * still editable and deletable the ordinary way - they just lose the one-tap
 * path, because at that distance "take it back" and "change history" stop being
 * the same intention.
 */
export const UNDO_WINDOW_HOURS = 48;

export type MovementType = 'expense' | 'income' | 'transfer' | 'fund' | 'release' | 'move' | 'adjust';

export interface Movement {
  /** `tx:<id>`, `alloc:<id>` or `adj:<id>` - unique across the three tables. */
  id: string;
  type: MovementType;
  /** What happened, in the words the user would use. */
  title: string;
  subtitle: string | null;
  /** Signed against the user's free money: a fill-up ties money up, so it reads negative. */
  amount: string;
  currency: string;
  at: string;
  recordedAt: string;
  undoable: boolean;
  /** Why not, when it is not. */
  blockedReason: string | null;
  accountId: string | null;
  budgetId: string | null;
}

function withinWindow(recordedAt: Date, now = new Date()): boolean {
  return now.getTime() - recordedAt.getTime() <= UNDO_WINDOW_HOURS * 3_600_000;
}

const tooOld = `Recorded more than ${UNDO_WINDOW_HOURS} hours ago. Edit or delete it instead - undo is for the mistake you just made.`;

/**
 * The recent-movements feed.
 *
 * Three tables, one list. Pulling `limit` from each and merging is deliberate:
 * a day of heavy spending should not push a fill-up out of the feed just because
 * it lives in a different table.
 */
export async function movements(user: AuthUser, limit = 25) {
  const now = new Date();
  const [txs, allocations, adjustments] = await Promise.all([
    prisma.transaction.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: limit,
      include: {
        account: { select: { id: true, name: true } },
        transferAccount: { select: { id: true, name: true } },
        category: { select: { name: true } },
        budget: { select: { id: true, name: true } },
      },
    }),
    prisma.budgetAllocation.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: limit * 2, // moves arrive in pairs and collapse into one row below
      include: {
        account: { select: { id: true, name: true } },
        budget: { select: { id: true, name: true, currency: true } },
      },
    }),
    prisma.budgetAdjustment.findMany({
      where: { userId: user.id, automatic: false },
      orderBy: { createdAt: 'desc' },
      take: limit,
      include: { budget: { select: { id: true, name: true, currency: true } } },
    }),
  ]);

  const rows: Movement[] = [];

  for (const tx of txs) {
    const type: MovementType =
      tx.kind === TxKind.INCOME ? 'income' : tx.kind === TxKind.TRANSFER ? 'transfer' : 'expense';
    const title =
      tx.kind === TxKind.TRANSFER
        ? `Moved money to ${tx.transferAccount?.name ?? 'another wallet'}`
        : (tx.payee ?? tx.category?.name ?? (tx.kind === TxKind.INCOME ? 'Money in' : 'Money out'));

    rows.push({
      id: `tx:${tx.id}`,
      type,
      title,
      subtitle:
        tx.kind === TxKind.TRANSFER
          ? `From ${tx.account.name}`
          : tx.budget
            ? `${tx.account.name} · ${tx.budget.name}`
            : tx.account.name,
      amount: (tx.kind === TxKind.INCOME ? tx.amount : tx.amount.neg()).toFixed(2),
      currency: tx.currency,
      at: tx.date.toISOString(),
      recordedAt: tx.createdAt.toISOString(),
      undoable: withinWindow(tx.createdAt, now),
      blockedReason: withinWindow(tx.createdAt, now) ? null : tooOld,
      accountId: tx.accountId,
      budgetId: tx.budgetId,
    });
  }

  // A move is two allocation rows. Show it once, and undo it as one thing -
  // half-undoing a move would duplicate money or destroy it.
  const seenGroups = new Set<string>();
  for (const a of allocations) {
    if (a.groupId) {
      if (seenGroups.has(a.groupId)) continue;
      seenGroups.add(a.groupId);
    }
    const isMove = a.groupId !== null;
    const isFund = a.kind === BudgetAllocationKind.FUND;

    rows.push({
      id: `alloc:${a.id}`,
      type: isMove ? 'move' : isFund ? 'fund' : 'release',
      title: isMove
        ? `Moved money into ${a.budget.name}`
        : isFund
          ? `Set aside for ${a.budget.name}`
          : `Gave back from ${a.budget.name}`,
      subtitle: a.account.name,
      // A fill-up does not change what you own, but it does change what you can
      // spend - which is what this column is about.
      amount: a.amount.toFixed(2),
      currency: a.budget.currency,
      at: a.date.toISOString(),
      recordedAt: a.createdAt.toISOString(),
      undoable: withinWindow(a.createdAt, now),
      blockedReason: withinWindow(a.createdAt, now) ? null : tooOld,
      accountId: a.accountId,
      budgetId: a.budgetId,
    });
  }

  for (const adj of adjustments) {
    rows.push({
      id: `adj:${adj.id}`,
      type: 'adjust',
      title: `${adj.amount.gte(0) ? 'Raised' : 'Cut'} ${adj.budget.name}`,
      subtitle: adj.reason,
      amount: adj.amount.toFixed(2),
      currency: adj.budget.currency,
      at: adj.date.toISOString(),
      recordedAt: adj.createdAt.toISOString(),
      undoable: withinWindow(adj.createdAt, now),
      blockedReason: withinWindow(adj.createdAt, now) ? null : tooOld,
      accountId: null,
      budgetId: adj.budgetId,
    });
  }

  return {
    items: rows
      .sort((a, b) => (a.recordedAt < b.recordedAt ? 1 : a.recordedAt > b.recordedAt ? -1 : 0))
      .slice(0, limit),
    undoWindowHours: UNDO_WINDOW_HOURS,
  };
}

/** What a movement id refers to. */
function parseMovementId(id: string): { table: 'tx' | 'alloc' | 'adj'; id: string } {
  const [table, ...rest] = id.split(':');
  const rowId = rest.join(':');
  if (!rowId || (table !== 'tx' && table !== 'alloc' && table !== 'adj')) {
    throw new BadRequestError('That is not a movement Santim recognises.');
  }
  return { table, id: rowId };
}

export interface UndoResult {
  undone: MovementType;
  /** One line for the toast, written as the reversal that just happened. */
  message: string;
}

/**
 * Take a movement back, leaving nothing behind.
 *
 * Refusals are the interesting part. Undoing a fill-up whose money has since
 * been spent would leave the plan holding money no wallet is backing, so the
 * invariant proof stops it and says so. The user's next step is obvious: undo
 * the spending first.
 */
export async function undo(user: AuthUser, movementId: string): Promise<UndoResult> {
  const target = parseMovementId(movementId);

  if (target.table === 'tx') {
    const tx = await prisma.transaction.findFirst({
      where: { id: target.id, userId: user.id },
      include: { account: { select: { name: true } } },
    });
    if (!tx) throw new NotFoundError('That movement is already gone.');
    if (!withinWindow(tx.createdAt)) throw new BadRequestError(tooOld);

    const { budgetId } = await deleteTransaction(user.id, tx.id);
    if (budgetId) {
      const { afterSpend } = await import('../budgets/budgets.service.js');
      await afterSpend(user.id, budgetId);
    }

    return {
      undone: tx.kind === TxKind.INCOME ? 'income' : tx.kind === TxKind.TRANSFER ? 'transfer' : 'expense',
      message:
        tx.kind === TxKind.INCOME
          ? `Took back ${tx.amount.toFixed(2)} ${tx.currency} of income.`
          : tx.kind === TxKind.TRANSFER
            ? `The ${tx.amount.toFixed(2)} ${tx.currency} move is undone.`
            : `${tx.amount.toFixed(2)} ${tx.currency} is back in "${tx.account.name}".`,
    };
  }

  if (target.table === 'alloc') {
    return withMoneyLock(user.id, async (tx) => {
      const row = await tx.budgetAllocation.findFirst({
        where: { id: target.id, userId: user.id },
        include: { budget: { select: { name: true, currency: true } }, account: { select: { name: true } } },
      });
      if (!row) throw new NotFoundError('That movement is already gone.');
      if (!withinWindow(row.createdAt)) throw new BadRequestError(tooOld);

      const wasMove = row.groupId !== null;
      if (wasMove) {
        // Both halves of the move, plus any automatic raise it needed to fit -
        // rolled back before the rows that record them are removed.
        const raises = await tx.budgetAdjustment.findMany({
          where: { userId: user.id, groupId: row.groupId! },
        });
        for (const raise of raises) {
          const budget = await tx.budget.findUnique({ where: { id: raise.budgetId } });
          if (budget) {
            await tx.budget.update({
              where: { id: budget.id },
              data: { plannedAmount: budget.plannedAmount.sub(raise.amount) },
            });
          }
        }
        await tx.budgetAdjustment.deleteMany({ where: { userId: user.id, groupId: row.groupId! } });
        await tx.budgetAllocation.deleteMany({ where: { userId: user.id, groupId: row.groupId! } });
      } else {
        await tx.budgetAllocation.delete({ where: { id: row.id } });
      }

      await assertSound(
        tx,
        user.id,
        row.kind === BudgetAllocationKind.FUND
          ? `That money has already been spent, so it cannot be un-set-aside:`
          : `Undoing that give-back would not add up:`,
      );

      const amount = row.amount.abs().toFixed(2);
      return {
        undone: wasMove ? ('move' as const) : row.kind === BudgetAllocationKind.FUND ? ('fund' as const) : ('release' as const),
        message: wasMove
          ? `The ${amount} ${row.budget.currency} move is undone.`
          : row.kind === BudgetAllocationKind.FUND
            ? `${amount} ${row.budget.currency} is free again in "${row.account.name}".`
            : `${amount} ${row.budget.currency} is back in "${row.budget.name}".`,
      };
    });
  }

  return withMoneyLock(user.id, async (tx) => {
    const row = await tx.budgetAdjustment.findFirst({
      where: { id: target.id, userId: user.id },
      include: { budget: true },
    });
    if (!row) throw new NotFoundError('That movement is already gone.');
    if (!withinWindow(row.createdAt)) throw new BadRequestError(tooOld);
    if (row.automatic) {
      throw new BadRequestError(
        'Santim raised this plan to cover a spend. Undo the spend and the raise goes with it.',
      );
    }

    const restored = row.budget.plannedAmount.sub(row.amount);
    if (restored.lte(0)) {
      throw new BadRequestError(
        `Undoing that would take "${row.budget.name}" to ${restored.toFixed(2)} ${row.budget.currency}, which is not a plan any more.`,
      );
    }

    const { fundedThisCycle } = await import('../../core/money/postings.js');
    const funded = await fundedThisCycle(tx, row.budget);
    if (restored.lt(funded)) {
      throw new BadRequestError(
        `"${row.budget.name}" holds ${funded.toFixed(2)} ${row.budget.currency}, which is more than the ${restored.toFixed(2)} it would go back to. Give some back first.`,
      );
    }

    await tx.budgetAdjustment.delete({ where: { id: row.id } });
    await tx.budget.update({ where: { id: row.budget.id }, data: { plannedAmount: restored } });

    return {
      undone: 'adjust' as const,
      message: `"${row.budget.name}" is back to ${restored.toFixed(2)} ${row.budget.currency}.`,
    };
  });
}

// ---------------------------------------------------------------------------
// The Money Doctor
// ---------------------------------------------------------------------------

/**
 * A plain-language health check on the user's own books, plus everything they
 * need to act on: what is reserved where, what is free, and where the bank
 * disagrees with us.
 */
export async function health(user: AuthUser, currency?: string) {
  const [report, snap, accounts, budgets] = await Promise.all([
    inspect(user.id),
    loadSnapshot(user.id),
    prisma.account.findMany({
      where: { userId: user.id, archived: false },
      select: { id: true, name: true, currency: true, icon: true, color: true },
    }),
    prisma.budget.findMany({
      where: { userId: user.id, state: 'ACTIVE' },
      select: { id: true, name: true, currency: true, icon: true, color: true },
    }),
  ]);

  const cur = (currency ?? accounts[0]?.currency ?? 'ETB').toUpperCase();
  const { driftReport } = await import('../accounts/accounts.service.js');
  const drift = await driftReport(user);

  return {
    healthy: report.healthy && drift.items.length === 0,
    checkedAt: report.checkedAt,
    /** Books that do not balance. Empty is the normal, expected state. */
    problems: report.violations,
    /** Wallets where the bank's own figure disagrees with ours. */
    drift: drift.items,
    currency: cur,
    money: {
      real: accounts
        .filter((a) => a.currency === cur)
        .reduce((s, a) => s.add(realOf(snap, a.id)), ZERO)
        .toFixed(2),
      reserved: accounts
        .filter((a) => a.currency === cur)
        .reduce((s, a) => s.add(heldOf(snap, a.id)), ZERO)
        .toFixed(2),
      readyToAssign: readyToAssign(snap, cur).toFixed(2),
    },
    wallets: accounts
      .filter((a) => a.currency === cur)
      .map((a) => ({
        ...a,
        real: realOf(snap, a.id).toFixed(2),
        reserved: heldOf(snap, a.id).toFixed(2),
        free: availableOf(snap, a.id).toFixed(2),
      })),
    plans: budgets
      .filter((b) => b.currency === cur)
      .map((b) => ({ ...b, holding: potOf(snap, b.id).toFixed(2) }))
      .filter((b) => Number(b.holding) !== 0),
  };
}

/** Put the books right, and say exactly what was moved and why. */
export async function fix(user: AuthUser) {
  const result = await repair(user.id);
  if (result.actions.length > 0) {
    const { notify } = await import('../notifications/notifications.service.js');
    await notify(
      user.id,
      'money_repaired',
      result.actions.length === 1
        ? result.actions[0]!.explanation
        : `Money Doctor made ${result.actions.length} corrections so your wallets and plans agree again.`,
      '/settings?tab=money-doctor',
    );
  }
  return result;
}

/**
 * Free money, per currency: what you have that is not in any plan. The single
 * most useful number in envelope budgeting, and until now not computed anywhere.
 */
export async function assignable(user: AuthUser) {
  const snap = await loadSnapshot(user.id);
  const currencies = [...new Set(snap.accounts.filter((a) => !a.archived).map((a) => a.currency))];

  return {
    items: currencies.map((currency) => ({
      currency,
      amount: readyToAssign(snap, currency).toFixed(2),
    })),
  };
}

export type { Prisma };
