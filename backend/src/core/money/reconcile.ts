/**
 * Checking, and where necessary repairing, the books.
 *
 * Nothing in Santim ever verified that its two ledgers agreed. That is the root
 * of every money bug it has had: a wrong number could sit on a screen for months
 * because no code path was ever going to notice. This module is that code path -
 * run from a script, from the app's own Money Doctor screen, and in CI.
 *
 * The repair is deliberately conservative and always explainable. It only ever
 * gives reserved money *back* to the wallet holding it; it never invents cash,
 * never deletes a transaction, and never touches anything it cannot describe in
 * one sentence to the person it belongs to.
 */
import { BudgetAllocationKind, Prisma } from '../prisma.js';
import { prisma } from '../db.js';
import { loadSnapshot } from './balances.js';
import { withMoneyLock } from './lock.js';
import { ZERO, checkInvariants, splitPair, type Violation } from './ledger.js';

export interface DriftReport {
  userId: string;
  checkedAt: string;
  healthy: boolean;
  violations: Violation[];
  totals: {
    accounts: number;
    plans: number;
    reservations: number;
  };
}

async function nameMaps(userId: string) {
  const [accounts, budgets] = await Promise.all([
    prisma.account.findMany({ where: { userId }, select: { id: true, name: true } }),
    prisma.budget.findMany({ where: { userId }, select: { id: true, name: true } }),
  ]);
  return {
    accounts: new Map(accounts.map((a) => [a.id, a.name])),
    budgets: new Map(budgets.map((b) => [b.id, b.name])),
  };
}

/** Read-only. Tells you whether one user's money adds up, and where it does not. */
export async function inspect(userId: string): Promise<DriftReport> {
  const [snap, names] = await Promise.all([loadSnapshot(userId), nameMaps(userId)]);
  const violations = checkInvariants(snap, names);

  return {
    userId,
    checkedAt: new Date().toISOString(),
    healthy: violations.length === 0,
    violations,
    totals: {
      accounts: snap.accounts.length,
      plans: snap.pots.size,
      reservations: snap.held.size,
    },
  };
}

export interface RepairAction {
  kind: 'released' | 'rebalanced';
  budgetId: string;
  accountId: string;
  amount: string;
  /** Written for the user, not for a log file. */
  explanation: string;
}

export interface RepairResult extends DriftReport {
  actions: RepairAction[];
  /** What is still wrong after the repair - should be empty. */
  remaining: Violation[];
}

/**
 * Put a user's books back in balance.
 *
 * Two shapes of damage, two repairs:
 *
 *  - **A wallet promising more than it holds** (I3/I5). Something removed the
 *    money underneath a reservation - a deleted income, a lowered opening
 *    balance. The excess is given back to the plans holding it, newest
 *    reservation first, because the newest is the one most likely to be the
 *    mistake.
 *  - **A negative reservation** (I2). More was released from a wallet than was
 *    ever held there, so the plan's money is recorded in the wrong place. The
 *    shortfall is moved off the plan's largest healthy share, which leaves the
 *    pot untouched and simply corrects where it is held.
 */
export async function repair(userId: string): Promise<RepairResult> {
  const actions: RepairAction[] = [];

  await withMoneyLock(userId, async (tx) => {
    const names = await nameMaps(userId);
    const now = new Date();

    // --- I2: reservations recorded against the wrong wallet -----------------
    let snap = await loadSnapshot(userId, {}, tx);
    for (const [key, amount] of snap.held) {
      if (amount.gte(0)) continue;
      const { accountId, budgetId } = splitPair(key);
      const short = amount.abs();

      const donors = [...snap.held.entries()]
        .map(([k, v]) => ({ ...splitPair(k), amount: v }))
        .filter((s) => s.budgetId === budgetId && s.accountId !== accountId && s.amount.gt(0))
        .sort((a, b) => b.amount.comparedTo(a.amount));

      let left = short;
      for (const donor of donors) {
        if (left.lte(0)) break;
        const slice = Prisma.Decimal.min(left, donor.amount);
        await tx.budgetAllocation.createMany({
          data: [
            {
              userId,
              budgetId,
              accountId: donor.accountId,
              kind: BudgetAllocationKind.RELEASE,
              amount: slice.neg(),
              date: now,
              note: 'Money Doctor: reservation moved to where the spending came from',
            },
            {
              userId,
              budgetId,
              accountId,
              kind: BudgetAllocationKind.FUND,
              amount: slice,
              date: now,
              note: 'Money Doctor: reservation corrected',
            },
          ],
        });
        actions.push({
          kind: 'rebalanced',
          budgetId,
          accountId,
          amount: slice.toFixed(2),
          explanation: `Moved ${slice.toFixed(2)} of "${names.budgets.get(budgetId) ?? 'a plan'}" from "${names.accounts.get(donor.accountId) ?? 'another wallet'}" to "${names.accounts.get(accountId) ?? 'this wallet'}", where the spending actually came from.`,
        });
        left = left.sub(slice);
      }
    }

    // --- I3/I5: wallets that promised more than they hold --------------------
    snap = await loadSnapshot(userId, {}, tx);
    for (const [accountId, heldHere] of snap.heldPerAccount) {
      const real = snap.real.get(accountId) ?? ZERO;
      let excess = heldHere.sub(real);
      if (excess.lte(0)) continue;

      // Newest reservation first: the most recent one is the likeliest mistake,
      // and unwinding it disturbs the least history.
      const rows = await tx.budgetAllocation.findMany({
        where: { userId, accountId },
        orderBy: { createdAt: 'desc' },
      });
      const perPlan = new Map<string, Prisma.Decimal>();
      for (const row of rows) {
        perPlan.set(row.budgetId, (perPlan.get(row.budgetId) ?? ZERO).add(row.amount));
      }

      for (const row of rows) {
        if (excess.lte(0)) break;
        const available = snap.held.get(`${accountId} ${row.budgetId}`) ?? ZERO;
        if (available.lte(0)) continue;
        const slice = Prisma.Decimal.min(excess, available);

        await tx.budgetAllocation.create({
          data: {
            userId,
            budgetId: row.budgetId,
            accountId,
            kind: BudgetAllocationKind.RELEASE,
            amount: slice.neg(),
            date: now,
            note: 'Money Doctor: given back because the wallet no longer holds it',
          },
        });
        actions.push({
          kind: 'released',
          budgetId: row.budgetId,
          accountId,
          amount: slice.toFixed(2),
          explanation: `"${names.accounts.get(accountId) ?? 'A wallet'}" no longer holds enough for everything reserved in it, so ${slice.toFixed(2)} was given back from "${names.budgets.get(row.budgetId) ?? 'a plan'}".`,
        });

        excess = excess.sub(slice);
        snap = await loadSnapshot(userId, {}, tx);
      }
    }
  });

  const after = await inspect(userId);
  return { ...after, actions, remaining: after.violations };
}

/** Every user, for the CI check and the one-off migration sweep. */
export async function inspectAll(limit = 5_000): Promise<DriftReport[]> {
  const users = await prisma.user.findMany({ select: { id: true }, take: limit });
  const reports: DriftReport[] = [];
  for (const user of users) reports.push(await inspect(user.id));
  return reports;
}
