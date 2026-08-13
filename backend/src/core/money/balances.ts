/**
 * The one place that reads money out of the database.
 *
 * Nothing else in the codebase may derive a balance. Before this module there
 * were four separate implementations of "what is in this account" - three of
 * them subtly different and one of them (the household panel) simply wrong,
 * ignoring transfers and reservations entirely. Any figure disagreeing with any
 * other figure is a bug the user experiences as the app lying to them.
 *
 * Every query here is an aggregate: the rows never leave Postgres. The results
 * are handed to the pure arithmetic in `ledger.ts`, which is where the actual
 * rules live.
 */
import { Prisma, TxKind } from '../prisma.js';
import { prisma } from '../db.js';
import type { MoneyTx } from './lock.js';
import {
  ZERO,
  type AccountSeed,
  type CashRow,
  type HoldRow,
  type LedgerSnapshot,
  type Money,
  type PlanSpendRow,
  pairKey,
  readyToAssign as computeReadyToAssign,
  sharesOfBudget,
  snapshot,
} from './ledger.js';

/** Narrowing a snapshot to pretend a given row does not exist - used by edits. */
export interface SnapshotOptions {
  /** Compute as if this transaction had never been written. */
  excludeTxId?: string;
  /** Compute as if this allocation had never been written. */
  excludeAllocationId?: string;
}

function db(tx?: MoneyTx) {
  return tx ?? prisma;
}

/**
 * Every money figure for one user, in one pass.
 *
 * Five aggregate queries, run together. That is the same order of work the old
 * per-call-site derivations did, for a result that is complete and consistent
 * rather than partial and occasionally contradictory.
 */
export async function loadSnapshot(
  userId: string,
  opts: SnapshotOptions = {},
  tx?: MoneyTx,
): Promise<LedgerSnapshot> {
  const client = db(tx);
  const notThisTx = opts.excludeTxId ? { id: { not: opts.excludeTxId } } : {};
  const notThisAlloc = opts.excludeAllocationId ? { id: { not: opts.excludeAllocationId } } : {};

  const [accounts, cashOut, transfersIn, holds, spends] = await Promise.all([
    client.account.findMany({
      where: { userId },
      select: { id: true, currency: true, openingBalance: true, archived: true },
    }),
    // Money entering or leaving the account named on the row.
    client.transaction.groupBy({
      by: ['accountId', 'kind'],
      where: { userId, ...notThisTx },
      _sum: { amount: true },
    }),
    // The other end of a transfer. `transferAmount` is always populated for
    // transfers - equal to `amount` unless the two wallets hold different
    // currencies - so this sum is correct across currencies too.
    client.transaction.groupBy({
      by: ['transferAccountId'],
      where: {
        userId,
        kind: TxKind.TRANSFER,
        transferAccountId: { not: null },
        ...notThisTx,
      },
      _sum: { transferAmount: true },
    }),
    // Fill-ups and give-backs, signed.
    client.budgetAllocation.groupBy({
      by: ['accountId', 'budgetId'],
      where: { userId, ...notThisAlloc },
      _sum: { amount: true },
    }),
    // Plan spending, grouped by the wallet whose reservation it frees - which is
    // not always the wallet the cash left.
    client.transaction.groupBy({
      by: ['budgetSourceAccountId', 'budgetId'],
      where: {
        userId,
        kind: TxKind.EXPENSE,
        budgetId: { not: null },
        budgetSourceAccountId: { not: null },
        ...notThisTx,
      },
      _sum: { amount: true },
    }),
  ]);

  const seeds: AccountSeed[] = accounts.map((a) => ({
    id: a.id,
    currency: a.currency,
    openingBalance: a.openingBalance,
    archived: a.archived,
  }));

  // One synthetic row per aggregate group. The arithmetic only ever sums, so a
  // group of 4,000 expenses and a single row carrying their total are the same
  // thing to it - and this way the rows never cross the wire.
  const cash: CashRow[] = [];
  for (const row of cashOut) {
    cash.push({
      accountId: row.accountId,
      kind: row.kind as CashRow['kind'],
      amount: row._sum.amount ?? ZERO,
      // Handled by the transfersIn aggregate below, so this half must not
      // credit anything or the destination would be paid twice.
      transferAccountId: null,
    });
  }
  for (const row of transfersIn) {
    if (!row.transferAccountId) continue;
    cash.push({
      accountId: row.transferAccountId,
      kind: 'INCOME',
      amount: row._sum.transferAmount ?? ZERO,
    });
  }

  const holdRows: HoldRow[] = holds.map((h) => ({
    accountId: h.accountId,
    budgetId: h.budgetId,
    amount: h._sum.amount ?? ZERO,
  }));

  const spendRows: PlanSpendRow[] = [];
  for (const s of spends) {
    if (!s.budgetSourceAccountId || !s.budgetId) continue;
    spendRows.push({
      budgetId: s.budgetId,
      budgetSourceAccountId: s.budgetSourceAccountId,
      amount: s._sum.amount ?? ZERO,
    });
  }

  return snapshot(seeds, cash, holdRows, spendRows);
}

// ---------------------------------------------------------------------------
// Readers - all of them thin, all of them derived from one snapshot
// ---------------------------------------------------------------------------

export function realOf(snap: LedgerSnapshot, accountId: string): Money {
  return snap.real.get(accountId) ?? ZERO;
}

export function heldOf(snap: LedgerSnapshot, accountId: string): Money {
  return snap.heldPerAccount.get(accountId) ?? ZERO;
}

export function availableOf(snap: LedgerSnapshot, accountId: string): Money {
  return snap.available.get(accountId) ?? ZERO;
}

export function potOf(snap: LedgerSnapshot, budgetId: string): Money {
  return snap.pots.get(budgetId) ?? ZERO;
}

/** What one wallet is holding for one plan. The unit of reservation. */
export function heldFor(snap: LedgerSnapshot, accountId: string, budgetId: string): Money {
  return snap.held.get(pairKey(accountId, budgetId)) ?? ZERO;
}

/** Where a plan's money is sitting, largest share first. */
export function sharesOf(snap: LedgerSnapshot, budgetId: string) {
  return sharesOfBudget(snap.held, budgetId);
}

/** Free money in one currency: not reserved, not archived. */
export function readyToAssign(snap: LedgerSnapshot, currency: string): Money {
  return computeReadyToAssign(snap.accounts, snap.real, snap.heldPerAccount, currency);
}

/** Everything reserved across a currency's wallets. */
export function lockedTotal(snap: LedgerSnapshot, currency: string): Money {
  const cur = currency.toUpperCase();
  let total = ZERO;
  for (const account of snap.accounts) {
    if (account.archived || account.currency.toUpperCase() !== cur) continue;
    total = total.add(heldOf(snap, account.id));
  }
  return total;
}

/** Real money across a currency's wallets, reservations included. */
export function realTotal(snap: LedgerSnapshot, currency: string): Money {
  const cur = currency.toUpperCase();
  let total = ZERO;
  for (const account of snap.accounts) {
    if (account.archived || account.currency.toUpperCase() !== cur) continue;
    total = total.add(realOf(snap, account.id));
  }
  return total;
}

/**
 * Convenience for the many callers that want one account's numbers and nothing
 * else. Still a full snapshot underneath - consistency beats shaving a query,
 * and partial derivations are exactly what produced the bugs this module exists
 * to end.
 */
export async function accountFigures(
  userId: string,
  accountId: string,
  opts: SnapshotOptions = {},
): Promise<{ real: Money; held: Money; available: Money }> {
  const snap = await loadSnapshot(userId, opts);
  return {
    real: realOf(snap, accountId),
    held: heldOf(snap, accountId),
    available: availableOf(snap, accountId),
  };
}

export { type LedgerSnapshot, type Money };
export const zero: Prisma.Decimal = ZERO;
