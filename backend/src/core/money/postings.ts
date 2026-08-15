/**
 * The only code in Santim allowed to move money.
 *
 * Transactions, fill-ups, give-backs, plan-to-plan moves, raises, cuts and undos
 * all pass through here. Nothing else may write `transactions`,
 * `budget_allocations` or `budget_adjustments` - not the Money Tab, not the
 * recurring engine, not the SMS inbox. Every one of those used to write directly,
 * which is why lending money could silently spend a plan's reserved cash and a
 * rent rule could overdraw a wallet nobody was watching.
 *
 * Three things make this safe rather than merely tidy:
 *
 *  1. **One lock.** Every operation runs inside `withMoneyLock`, so check-then-write
 *     stops being a race. Two requests cannot both spend the same 500.
 *  2. **One proof.** Every operation ends by re-deriving the books and checking
 *     I2-I5. Bespoke guards give good error messages on the paths users actually
 *     hit; the proof catches everything else, including the cases nobody thought
 *     to guard - deleting the income that funded a plan, lowering an opening
 *     balance, archiving a wallet with reservations on it.
 *  3. **One id.** A replayed write returns the row it already made instead of
 *     making a second one.
 */
import { randomUUID } from 'node:crypto';
import {
  BudgetAllocationKind,
  BudgetKind,
  BudgetState,
  BudgetType,
  CategoryKind,
  Prisma,
  TxKind,
  type Budget,
} from '../prisma.js';
import { BadRequestError, ConflictError, NotFoundError } from '../errors.js';
import { env } from '../../config/env.js';
import { cycleIndexForDate } from '../../modules/budgets/budgets.periods.js';
import { loadSnapshot } from './balances.js';
import { withMoneyLock, type MoneyTx } from './lock.js';
import {
  ZERO,
  checkInvariants,
  dec,
  sharesOfBudget,
  type Money,
} from './ledger.js';

// ---------------------------------------------------------------------------
// Shared shapes
// ---------------------------------------------------------------------------

/** Where the money comes from when a plan cannot cover a spend. */
export type Cover =
  | { from: 'BUDGET'; budgetId: string }
  | { from: 'ACCOUNT'; accountId: string };

export interface PostTransactionInput {
  kind: TxKind;
  amount: number | string | Money;
  /** Defaults to the account's currency, and must match it if given. */
  currency?: string;
  date: Date;
  accountId: string;
  transferAccountId?: string | null;
  /** What the destination receives. Required when the wallets differ in currency. */
  transferAmount?: number | string | Money | null;
  categoryId?: string | null;
  /** Null means unplanned - the one and only representation of it. */
  budgetId?: string | null;
  /** Whose reservation to free. Resolved automatically when there is no choice. */
  budgetSourceAccountId?: string | null;
  cover?: Cover | null;
  note?: string | null;
  payee?: string | null;
  tags?: string[];
  receiptUrl?: string | null;
  recurringRuleId?: string | null;
  clientOpId?: string | null;
}

export interface PatchTransactionInput {
  amount?: number | string | Money;
  currency?: string;
  date?: Date;
  accountId?: string;
  transferAccountId?: string;
  transferAmount?: number | string | Money | null;
  categoryId?: string;
  budgetSourceAccountId?: string;
  note?: string | null;
  payee?: string | null;
  tags?: string[];
  receiptUrl?: string | null;
}

/**
 * Machine-readable detail on a refusal, so the clients can offer the right next
 * step instead of just printing a sentence. A short plan offers "cover from";
 * a short wallet offers "move money in".
 */
export interface ShortfallDetails {
  reason: 'PLAN_SHORT' | 'ACCOUNT_SHORT';
  shortfall: string;
  currency: string;
  budgetId?: string;
  accountId?: string;
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

const money = (v: number | string | Money): Money => dec(v as never);

async function ownedAccount(tx: MoneyTx, userId: string, id: string) {
  const account = await tx.account.findFirst({ where: { id, userId } });
  if (!account) throw new NotFoundError('Account not found');
  return account;
}

async function ownedBudget(tx: MoneyTx, userId: string, id: string): Promise<Budget> {
  const budget = await tx.budget.findFirst({ where: { id, userId } });
  if (!budget) throw new NotFoundError('Budget plan not found');
  return budget;
}

async function ownedCategory(tx: MoneyTx, userId: string, id: string, kind: TxKind) {
  const category = await tx.category.findFirst({ where: { id, userId } });
  if (!category) throw new NotFoundError('Category not found');
  const expected = kind === TxKind.INCOME ? CategoryKind.INCOME : CategoryKind.EXPENSE;
  if (category.kind !== expected) {
    throw new BadRequestError(`"${category.name}" is a ${category.kind.toLowerCase()} category`);
  }
  return category;
}

/**
 * I6 - a wallet holds one currency, and money never enters it wearing another.
 * Without this a USD expense subtracts one-for-one from an ETB balance.
 */
function assertCurrency(given: string | undefined, account: { name: string; currency: string }) {
  if (!given) return account.currency;
  const want = given.toUpperCase();
  if (want !== account.currency.toUpperCase()) {
    throw new BadRequestError(
      `"${account.name}" holds ${account.currency}. Record this in ${account.currency}, or pick a ${want} wallet.`,
    );
  }
  return account.currency;
}

function assertOpenForWrites(account: { name: string; archived: boolean }) {
  if (account.archived) {
    throw new BadRequestError(
      `"${account.name}" is archived. Unarchive it before recording anything new against it.`,
    );
  }
}

/** Which cycle a plan expense belongs to - decided by its date (I7). */
async function cycleForDate(tx: MoneyTx, budget: Budget, date: Date): Promise<number> {
  if (budget.kind !== BudgetKind.RECURRING) return 0;
  const past = await tx.budgetCycle.findMany({
    where: { budgetId: budget.id },
    select: { index: true, startedAt: true, endedAt: true },
  });
  return cycleIndexForDate(budget, date, past);
}

// ---------------------------------------------------------------------------
// The proof
// ---------------------------------------------------------------------------

/**
 * Re-derive the books and refuse the write if they no longer balance.
 *
 * This is the safety net that makes the whole model hold. Any operation that
 * would leave a wallet promising more than it holds, a reservation negative, or
 * an account overdrawn against its own plans, is rolled back with the invariant's
 * own explanation. It is what makes "delete the income that funded a plan" fail
 * loudly instead of corrupting the books in silence.
 */
export async function assertSound(tx: MoneyTx, userId: string, context?: string): Promise<void> {
  const snap = await loadSnapshot(userId, {}, tx);
  const [accounts, budgets] = await Promise.all([
    tx.account.findMany({ where: { userId }, select: { id: true, name: true } }),
    tx.budget.findMany({ where: { userId }, select: { id: true, name: true } }),
  ]);

  const violations = checkInvariants(snap, {
    accounts: new Map(accounts.map((a) => [a.id, a.name])),
    budgets: new Map(budgets.map((b) => [b.id, b.name])),
  });
  if (violations.length === 0) return;

  const first = violations[0]!;
  throw new ConflictError(
    context ? `${context} ${first.message}` : first.message,
    { invariant: first.code, violations: violations.slice(0, 5) },
  );
}

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

async function replayedTransaction(tx: MoneyTx, userId: string, clientOpId?: string | null) {
  if (!clientOpId) return null;
  return tx.transaction.findFirst({ where: { userId, clientOpId } });
}

// ---------------------------------------------------------------------------
// Covering a short plan (D3)
// ---------------------------------------------------------------------------

/**
 * Top a plan up so it can cover a spend it is short for.
 *
 * Refusing an overspend outright reads as strict but teaches nothing: users work
 * around it by recording the spend as unplanned, which quietly destroys the
 * accuracy of both numbers. Naming where the money came from is the part that is
 * actually worth knowing.
 *
 * The plan's own amount is raised alongside, as an automatic adjustment, so
 * "planned" never ends up smaller than "funded" and the cycle history says
 * honestly that the plan grew mid-cycle.
 */
async function coverShortfall(
  tx: MoneyTx,
  userId: string,
  budget: Budget,
  shortfall: Money,
  cover: Cover,
  groupId: string,
  date: Date,
): Promise<void> {
  const snap = await loadSnapshot(userId, {}, tx);

  if (cover.from === 'ACCOUNT') {
    const account = await ownedAccount(tx, userId, cover.accountId);
    assertOpenForWrites(account);
    if (account.currency !== budget.currency) {
      throw new BadRequestError(
        `"${account.name}" holds ${account.currency}; "${budget.name}" is in ${budget.currency}.`,
      );
    }
    const free = snap.available.get(account.id) ?? ZERO;
    if (shortfall.gt(free)) {
      throw new BadRequestError(
        `"${account.name}" has ${free.toFixed(2)} ${account.currency} free - not enough to cover the ${shortfall.toFixed(2)} shortfall.`,
        { reason: 'ACCOUNT_SHORT', shortfall: shortfall.toFixed(2), currency: account.currency, accountId: account.id } satisfies ShortfallDetails,
      );
    }
    await tx.budgetAllocation.create({
      data: {
        userId,
        budgetId: budget.id,
        accountId: account.id,
        kind: BudgetAllocationKind.FUND,
        amount: shortfall,
        cycleIndex: budget.cycleIndex,
        date,
        groupId,
        note: `Covering an overspend from ${account.name}`,
      },
    });
  } else {
    const donor = await ownedBudget(tx, userId, cover.budgetId);
    if (donor.id === budget.id) {
      throw new BadRequestError('A plan cannot cover its own overspend.');
    }
    if (donor.currency !== budget.currency) {
      throw new BadRequestError(
        `"${donor.name}" is in ${donor.currency}; "${budget.name}" is in ${budget.currency}.`,
      );
    }
    await moveBetweenPlans(tx, userId, donor, budget, shortfall, groupId, date, snap.held);
  }

  // The plan is now genuinely bigger than it was planned to be. Say so.
  await tx.budgetAdjustment.create({
    data: {
      userId,
      budgetId: budget.id,
      amount: shortfall,
      cycleIndex: budget.cycleIndex,
      reason: 'Raised to cover an overspend',
      automatic: true,
      groupId,
      date,
    },
  });
  await tx.budget.update({
    where: { id: budget.id },
    data: { plannedAmount: budget.plannedAmount.add(shortfall) },
  });
}

/**
 * Shift a reservation from one plan to another without the cash moving.
 *
 * Both halves stay in the same wallet, which is the whole point: nothing about
 * where the money physically is has changed, only which envelope has a claim on
 * it. Drawn from the donor's largest shares first, spilling across wallets when
 * one share is not enough.
 */
async function moveBetweenPlans(
  tx: MoneyTx,
  userId: string,
  from: Budget,
  to: Budget,
  amount: Money,
  groupId: string,
  date: Date,
  held: Map<string, Money>,
): Promise<void> {
  const shares = sharesOfBudget(held, from.id).filter((s) => s.amount.gt(0));
  const pot = shares.reduce((s, x) => s.add(x.amount), ZERO);
  if (amount.gt(pot)) {
    throw new BadRequestError(
      `"${from.name}" only holds ${pot.toFixed(2)} ${from.currency}.`,
      { reason: 'PLAN_SHORT', shortfall: amount.sub(pot).toFixed(2), currency: from.currency, budgetId: from.id } satisfies ShortfallDetails,
    );
  }

  let left = amount;
  for (const share of shares) {
    if (left.lte(0)) break;
    const slice = Prisma.Decimal.min(left, share.amount);
    await tx.budgetAllocation.createMany({
      data: [
        {
          userId,
          budgetId: from.id,
          accountId: share.accountId,
          kind: BudgetAllocationKind.RELEASE,
          amount: slice.neg(),
          cycleIndex: from.cycleIndex,
          date,
          groupId,
          note: `Moved to ${to.name}`,
        },
        {
          userId,
          budgetId: to.id,
          accountId: share.accountId,
          kind: BudgetAllocationKind.FUND,
          amount: slice,
          cycleIndex: to.cycleIndex,
          date,
          groupId,
          note: `Moved from ${from.name}`,
        },
      ],
    });
    left = left.sub(slice);
  }
}

// ---------------------------------------------------------------------------
// Posting a transaction
// ---------------------------------------------------------------------------

interface PlanCharge {
  budget: Budget;
  releaseAccountId: string;
  cycleIndex: number;
  /** True when the payer is fronting money for a plan held in another wallet. */
  frontedBy: string | null;
}

/**
 * Resolve which reservation a plan spend frees, topping the plan up first if the
 * caller supplied a cover.
 */
async function resolvePlanCharge(
  tx: MoneyTx,
  userId: string,
  budgetId: string,
  amount: Money,
  payerId: string,
  requestedRelease: string | null | undefined,
  cover: Cover | null | undefined,
  groupId: string,
  date: Date,
  excludeTxId?: string,
): Promise<PlanCharge> {
  const budget = await ownedBudget(tx, userId, budgetId);

  // Money does not leave a saving plan as spending. It leaves by being given
  // back to a wallet, moved to another plan, or by converting the plan to a
  // spending one - all of which are deliberate acts with their own screens.
  //
  // The alternative was a Withdraw action, which is one tap and would let a
  // holiday fund quietly become grocery money. Giving it back first is one tap
  // more, and that tap is the entire point.
  if (budget.type === BudgetType.SAVING) {
    throw new BadRequestError(
      `"${budget.name}" is a saving plan, so it cannot be spent from directly. ` +
        'Give the money back to a wallet and spend it from there, or turn the plan ' +
        'into a spending plan first.',
      { reason: 'SAVING_PLAN_NOT_SPENDABLE', budgetId: budget.id },
    );
  }

  if (budget.state === BudgetState.CLOSED) {
    throw new BadRequestError(`"${budget.name}" is closed. Reopen it to spend from it.`);
  }
  if (budget.startsAt > date) {
    throw new BadRequestError(
      `"${budget.name}" starts on ${budget.startsAt.toISOString().slice(0, 10)}, so it cannot pay for something dated before that.`,
    );
  }

  let snap = await loadSnapshot(userId, { excludeTxId }, tx);
  let pot = snap.pots.get(budget.id) ?? ZERO;

  if (amount.gt(pot)) {
    const shortfall = amount.sub(pot);
    if (!cover) {
      throw new BadRequestError(
        pot.lte(0)
          ? `"${budget.name}" is empty. Choose where the ${amount.toFixed(2)} ${budget.currency} should come from.`
          : `"${budget.name}" has ${pot.toFixed(2)} ${budget.currency} left - ${shortfall.toFixed(2)} short. Choose where to cover it from.`,
        {
          reason: 'PLAN_SHORT',
          shortfall: shortfall.toFixed(2),
          currency: budget.currency,
          budgetId: budget.id,
        } satisfies ShortfallDetails,
      );
    }
    await coverShortfall(tx, userId, budget, shortfall, cover, groupId, date);
    snap = await loadSnapshot(userId, { excludeTxId }, tx);
    pot = snap.pots.get(budget.id) ?? ZERO;
  }

  const shares = sharesOfBudget(snap.held, budget.id).filter((s) => s.amount.gt(0));
  if (shares.length === 0) {
    throw new BadRequestError(`"${budget.name}" has no money in it yet.`);
  }

  // Prefer the wallet the money is actually leaving - if it holds a big enough
  // share, nothing is being fronted and the whole question disappears.
  const asked = requestedRelease
    ? shares.find((s) => s.accountId === requestedRelease)
    : undefined;
  const chosen =
    asked ??
    shares.find((s) => s.accountId === payerId && s.amount.gte(amount)) ??
    shares.find((s) => s.amount.gte(amount)) ??
    shares[0]!;

  if (amount.gt(chosen.amount)) {
    const biggest = shares[0]!;
    throw new BadRequestError(
      requestedRelease
        ? `Only ${chosen.amount.toFixed(2)} ${budget.currency} of "${budget.name}" is held in that wallet. The largest single share is ${biggest.amount.toFixed(2)}.`
        : `"${budget.name}" holds its money across several wallets; the largest single share is ${biggest.amount.toFixed(2)} ${budget.currency}. Say which wallet to take it off, or split the expense.`,
    );
  }

  return {
    budget,
    releaseAccountId: chosen.accountId,
    cycleIndex: await cycleForDate(tx, budget, date),
    frontedBy: chosen.accountId === payerId ? null : payerId,
  };
}

/**
 * Record a movement of money. The single entry point for every transaction in
 * the system, whoever is asking.
 */
export async function postTransaction(
  userId: string,
  input: PostTransactionInput,
  existingTx?: MoneyTx,
) {
  return withMoneyLock(
    userId,
    async (tx) => {
      const replay = await replayedTransaction(tx, userId, input.clientOpId);
      if (replay) return replay;

      const amount = money(input.amount);
      if (amount.lte(0)) throw new BadRequestError('An amount has to be greater than zero.');

      const account = await ownedAccount(tx, userId, input.accountId);
      const currency = assertCurrency(input.currency, account);

      // Editing history against an archived wallet is fine; adding to it is not.
      assertOpenForWrites(account);

      // The id is minted here so the cover movements can point at the spend that
      // caused them before it exists.
      const id = randomUUID();

      let categoryId: string | null = null;
      let transferAccountId: string | null = null;
      let transferAmount: Money | null = null;
      let transferRate: Prisma.Decimal | null = null;

      if (input.kind === TxKind.TRANSFER) {
        if (!input.transferAccountId) throw new BadRequestError('Pick where the money is going.');
        if (input.transferAccountId === account.id) {
          throw new BadRequestError('A transfer needs two different wallets.');
        }
        const destination = await ownedAccount(tx, userId, input.transferAccountId);
        assertOpenForWrites(destination);
        transferAccountId = destination.id;

        if (destination.currency === account.currency) {
          transferAmount = amount;
        } else {
          // I6 - crossing a currency without a rate is how money gets invented.
          if (input.transferAmount === undefined || input.transferAmount === null) {
            throw new BadRequestError(
              `"${account.name}" holds ${account.currency} and "${destination.name}" holds ${destination.currency}. Say how much ${destination.currency} arrived.`,
            );
          }
          transferAmount = money(input.transferAmount);
          if (transferAmount.lte(0)) {
            throw new BadRequestError('The amount that arrived has to be greater than zero.');
          }
          transferRate = transferAmount.div(amount);
        }
      } else {
        if (!input.categoryId) throw new BadRequestError('Pick a category.');
        const category = await ownedCategory(tx, userId, input.categoryId, input.kind);
        categoryId = category.id;
      }

      let charge: PlanCharge | null = null;
      if (input.kind === TxKind.EXPENSE && input.budgetId) {
        charge = await resolvePlanCharge(
          tx,
          userId,
          input.budgetId,
          amount,
          account.id,
          input.budgetSourceAccountId,
          input.cover,
          id,
          input.date,
        );
        if (charge.budget.currency !== currency) {
          throw new BadRequestError(
            `"${charge.budget.name}" is in ${charge.budget.currency}; this is ${currency}.`,
          );
        }
      }

      // The cash guard. Money that leaves a wallet may not overdraw it, and may
      // not eat what plans have already spoken for. The one exception is a plan
      // expense paid from the very wallet holding its reservation: that money is
      // already committed to this, so only the real balance matters.
      if (input.kind !== TxKind.INCOME) {
        const snap = await loadSnapshot(userId, {}, tx);
        const releasingHere = charge?.releaseAccountId === account.id;
        const ceiling = releasingHere
          ? (snap.real.get(account.id) ?? ZERO)
          : (snap.available.get(account.id) ?? ZERO);

        if (amount.gt(ceiling)) {
          throw new BadRequestError(
            releasingHere
              ? `"${account.name}" only holds ${ceiling.toFixed(2)} ${account.currency} right now.`
              : `"${account.name}" has ${ceiling.toFixed(2)} ${account.currency} free after money set aside in plans, and this needs ${amount.toFixed(2)}.`,
            {
              reason: 'ACCOUNT_SHORT',
              shortfall: amount.sub(ceiling).toFixed(2),
              currency: account.currency,
              accountId: account.id,
            } satisfies ShortfallDetails,
          );
        }
      }

      const created = await tx.transaction.create({
        data: {
          id,
          userId,
          kind: input.kind,
          amount,
          currency,
          date: input.date,
          accountId: account.id,
          transferAccountId,
          transferAmount,
          transferRate,
          categoryId,
          budgetId: charge?.budget.id ?? null,
          budgetCycle: charge?.cycleIndex ?? null,
          budgetSourceAccountId: charge?.releaseAccountId ?? null,
          note: input.note ?? null,
          payee: input.payee ?? null,
          tags: input.tags ?? [],
          receiptUrl: input.receiptUrl ?? null,
          recurringRuleId: input.recurringRuleId ?? null,
          clientOpId: input.clientOpId ?? null,
        },
      });

      await assertSound(tx, userId, 'That would not add up:');
      return created;
    },
    existingTx,
  );
}

/**
 * Edit a transaction in place.
 *
 * The plan a spend belongs to is deliberately not editable here: moving an
 * expense between envelopes changes which reservation it frees, and doing that
 * as a field update hides a two-sided movement inside what looks like a typo
 * correction. `movePlanSpend` does it explicitly.
 */
export async function patchTransaction(
  userId: string,
  id: string,
  patch: PatchTransactionInput,
  existingTx?: MoneyTx,
) {
  return withMoneyLock(
    userId,
    async (tx) => {
      const existing = await tx.transaction.findFirst({ where: { id, userId } });
      if (!existing) throw new NotFoundError('Transaction not found');

      const amount = patch.amount !== undefined ? money(patch.amount) : existing.amount;
      if (amount.lte(0)) throw new BadRequestError('An amount has to be greater than zero.');
      const date = patch.date ?? existing.date;

      const account = await ownedAccount(tx, userId, patch.accountId ?? existing.accountId);
      const currency = assertCurrency(patch.currency ?? existing.currency, account);

      if (patch.categoryId !== undefined) {
        if (existing.kind === TxKind.TRANSFER) {
          throw new BadRequestError('Transfers do not have a category.');
        }
        await ownedCategory(tx, userId, patch.categoryId, existing.kind);
      }

      let transferAccountId = existing.transferAccountId;
      let transferAmount = existing.transferAmount;
      let transferRate = existing.transferRate;

      if (existing.kind === TxKind.TRANSFER) {
        if (patch.transferAccountId !== undefined) {
          if (patch.transferAccountId === account.id) {
            throw new BadRequestError('A transfer needs two different wallets.');
          }
          transferAccountId = (await ownedAccount(tx, userId, patch.transferAccountId)).id;
        }
        const destination = await ownedAccount(tx, userId, transferAccountId!);
        if (destination.currency === account.currency) {
          transferAmount = amount;
          transferRate = null;
        } else {
          const given = patch.transferAmount ?? existing.transferAmount;
          if (given === undefined || given === null) {
            throw new BadRequestError(
              `"${account.name}" holds ${account.currency} and "${destination.name}" holds ${destination.currency}. Say how much ${destination.currency} arrived.`,
            );
          }
          transferAmount = money(given);
          transferRate = transferAmount.div(amount);
        }
      } else if (patch.transferAccountId !== undefined) {
        throw new BadRequestError('Only transfers have a destination wallet.');
      }

      // A plan spend re-resolves which reservation it frees, ignoring its own
      // prior effect so an unchanged edit cannot trip its own guard.
      let releaseAccountId = existing.budgetSourceAccountId;
      let cycleIndex = existing.budgetCycle;
      if (existing.budgetId) {
        const charge = await resolvePlanCharge(
          tx,
          userId,
          existing.budgetId,
          amount,
          account.id,
          patch.budgetSourceAccountId ?? existing.budgetSourceAccountId,
          null,
          existing.id,
          date,
          existing.id,
        );
        releaseAccountId = charge.releaseAccountId;
        cycleIndex = charge.cycleIndex;
        if (charge.budget.currency !== currency) {
          throw new BadRequestError(
            `"${charge.budget.name}" is in ${charge.budget.currency}; this is ${currency}.`,
          );
        }
      }

      if (existing.kind !== TxKind.INCOME) {
        const snap = await loadSnapshot(userId, { excludeTxId: existing.id }, tx);
        const releasingHere = releaseAccountId === account.id;
        const ceiling = releasingHere
          ? (snap.real.get(account.id) ?? ZERO)
          : (snap.available.get(account.id) ?? ZERO);
        if (amount.gt(ceiling)) {
          throw new BadRequestError(
            `"${account.name}" only has ${ceiling.toFixed(2)} ${account.currency} for this.`,
          );
        }
      }

      const updated = await tx.transaction.update({
        where: { id },
        data: {
          ...(patch.amount !== undefined ? { amount } : {}),
          ...(patch.date !== undefined ? { date } : {}),
          ...(patch.accountId !== undefined ? { accountId: account.id } : {}),
          ...(patch.currency !== undefined ? { currency } : {}),
          ...(patch.categoryId !== undefined ? { categoryId: patch.categoryId } : {}),
          ...(existing.kind === TxKind.TRANSFER
            ? { transferAccountId, transferAmount, transferRate }
            : {}),
          ...(existing.budgetId ? { budgetSourceAccountId: releaseAccountId, budgetCycle: cycleIndex } : {}),
          ...(patch.note !== undefined ? { note: patch.note } : {}),
          ...(patch.payee !== undefined ? { payee: patch.payee } : {}),
          ...(patch.tags !== undefined ? { tags: patch.tags } : {}),
          ...(patch.receiptUrl !== undefined ? { receiptUrl: patch.receiptUrl } : {}),
        },
      });

      await assertSound(tx, userId, 'That edit would not add up:');
      return updated;
    },
    existingTx,
  );
}

/**
 * Remove a transaction and everything Santim did on its behalf.
 *
 * A spend that was covered by raising its plan takes that raise - and the money
 * moved to fund it - with it. Leaving them behind would quietly inflate the plan
 * every time an overspent expense was deleted.
 */
export async function deleteTransaction(
  userId: string,
  id: string,
  existingTx?: MoneyTx,
): Promise<{ budgetId: string | null }> {
  return withMoneyLock(
    userId,
    async (tx) => {
      const existing = await tx.transaction.findFirst({ where: { id, userId } });
      if (!existing) throw new NotFoundError('Transaction not found');

      // Hand a captured bank message back to the inbox rather than leaving it
      // marked as recorded against a row that no longer exists.
      await tx.inboxMessage.updateMany({
        where: { transactionId: id, userId },
        data: { status: 'PENDING', transactionId: null, resolvedAt: null },
      });

      const automaticRaise = await tx.budgetAdjustment.findMany({
        where: { userId, groupId: id, automatic: true },
      });
      for (const raise of automaticRaise) {
        const budget = await tx.budget.findUnique({ where: { id: raise.budgetId } });
        if (budget) {
          await tx.budget.update({
            where: { id: budget.id },
            data: { plannedAmount: budget.plannedAmount.sub(raise.amount) },
          });
        }
      }
      await tx.budgetAdjustment.deleteMany({ where: { userId, groupId: id } });
      await tx.budgetAllocation.deleteMany({ where: { userId, groupId: id } });

      await tx.transaction.delete({ where: { id } });

      await assertSound(
        tx,
        userId,
        'Removing this would leave the books unbalanced:',
      );
      return { budgetId: existing.budgetId };
    },
    existingTx,
  );
}

// ---------------------------------------------------------------------------
// Reservations
// ---------------------------------------------------------------------------

export interface FundInput {
  accountId: string;
  amount: number | string | Money;
  date?: Date;
  note?: string | null;
  clientOpId?: string | null;
}

/** Set money aside in a plan. The cash stays put; it just stops being free. */
export async function fundPlan(
  userId: string,
  budgetId: string,
  input: FundInput,
  existingTx?: MoneyTx,
) {
  return withMoneyLock(userId, async (tx) => {
    if (input.clientOpId) {
      const replay = await tx.budgetAllocation.findFirst({
        where: { userId, clientOpId: input.clientOpId },
      });
      if (replay) return replay;
    }

    const budget = await ownedBudget(tx, userId, budgetId);
    if (budget.state === BudgetState.CLOSED) {
      throw new BadRequestError('This plan is closed. Reopen it before adding money.');
    }
    const account = await ownedAccount(tx, userId, input.accountId);
    assertOpenForWrites(account);
    if (account.currency !== budget.currency) {
      throw new BadRequestError(
        `"${account.name}" holds ${account.currency}; this plan is in ${budget.currency}.`,
      );
    }

    const amount = money(input.amount);
    if (amount.lte(0)) throw new BadRequestError('An amount has to be greater than zero.');

    const snap = await loadSnapshot(userId, {}, tx);
    const free = snap.available.get(account.id) ?? ZERO;
    if (amount.gt(free)) {
      throw new BadRequestError(
        `"${account.name}" has ${free.toFixed(2)} ${account.currency} free after money already set aside. This needs ${amount.toFixed(2)}.`,
        {
          reason: 'ACCOUNT_SHORT',
          shortfall: amount.sub(free).toFixed(2),
          currency: account.currency,
          accountId: account.id,
        } satisfies ShortfallDetails,
      );
    }

    // The one place the two plan types diverge in the money core.
    //
    // On a SPENDING plan, plannedAmount is a ceiling and filling past it is a
    // decision rather than an accident - `adjust` is what raises it, and the
    // message says so.
    //
    // On a SAVING plan nothing here is a cap. plannedAmount is a target (the
    // whole goal when one-time, the per-period contribution when recurring)
    // and goalAmount is a finish line. Refusing the contribution that happens
    // to land a little past either would force the user to go and edit the
    // goal before they could save - and the money is reserved either way.
    // Overshoot is surfaced by the client, not rejected here.
    if (budget.type === BudgetType.SPENDING) {
      const funded = await fundedThisCycle(tx, budget);
      const fillable = Prisma.Decimal.max(ZERO, budget.plannedAmount.sub(funded));
      if (amount.gt(fillable)) {
        throw new BadRequestError(
          fillable.lte(0)
            ? `"${budget.name}" is already filled to its planned ${budget.plannedAmount.toFixed(2)} ${budget.currency}. Raise the plan first if it needs to hold more.`
            : `"${budget.name}" can take ${fillable.toFixed(2)} ${budget.currency} more before hitting its planned ${budget.plannedAmount.toFixed(2)}.`,
        );
      }
    }

    const created = await tx.budgetAllocation.create({
      data: {
        userId,
        budgetId: budget.id,
        accountId: account.id,
        kind: BudgetAllocationKind.FUND,
        amount,
        cycleIndex: budget.cycleIndex,
        date: input.date ?? new Date(),
        note: input.note ?? null,
        clientOpId: input.clientOpId ?? null,
      },
    });

    await assertSound(tx, userId, 'That would not add up:');
    return created;
  }, existingTx);
}

/** Give money in a plan back to the wallet it is held in. */
export async function releasePlan(
  userId: string,
  budgetId: string,
  input: { accountId?: string; amount: number | string | Money; date?: Date; note?: string | null; clientOpId?: string | null },
  existingTx?: MoneyTx,
) {
  return withMoneyLock(userId, async (tx) => {
    if (input.clientOpId) {
      const replay = await tx.budgetAllocation.findFirst({
        where: { userId, clientOpId: input.clientOpId },
      });
      if (replay) return replay;
    }

    const budget = await ownedBudget(tx, userId, budgetId);
    const amount = money(input.amount);
    if (amount.lte(0)) throw new BadRequestError('An amount has to be greater than zero.');

    const snap = await loadSnapshot(userId, {}, tx);
    const shares = sharesOfBudget(snap.held, budget.id).filter((s) => s.amount.gt(0));
    if (shares.length === 0) throw new BadRequestError('This plan has no money to give back.');

    // The pot as a whole, not just one wallet's share. Checking only the share is
    // what used to let a give-back push a pot negative.
    const pot = snap.pots.get(budget.id) ?? ZERO;
    if (amount.gt(pot)) {
      throw new BadRequestError(
        `"${budget.name}" only holds ${pot.toFixed(2)} ${budget.currency}.`,
      );
    }

    const target = input.accountId
      ? shares.find((s) => s.accountId === input.accountId)
      : shares[0];
    if (!target) {
      throw new BadRequestError('None of this plan is held in that wallet.');
    }
    if (amount.gt(target.amount)) {
      throw new BadRequestError(
        `Only ${target.amount.toFixed(2)} ${budget.currency} of "${budget.name}" is held there. Give it back in parts, or pick the wallet with the largest share.`,
      );
    }

    const created = await tx.budgetAllocation.create({
      data: {
        userId,
        budgetId: budget.id,
        accountId: target.accountId,
        kind: BudgetAllocationKind.RELEASE,
        amount: amount.neg(),
        cycleIndex: budget.cycleIndex,
        date: input.date ?? new Date(),
        note: input.note ?? null,
        clientOpId: input.clientOpId ?? null,
      },
    });

    await assertSound(tx, userId, 'That would not add up:');
    return created;
  }, existingTx);
}

/**
 * Move money straight from one plan to another.
 *
 * Give-back-then-refill was the only way to do this, which is two operations, and
 * the refill could be blocked by the receiving plan's fill cap even though the
 * money was already yours and already set aside.
 */
export async function movePlanMoney(
  userId: string,
  fromBudgetId: string,
  toBudgetId: string,
  amountInput: number | string | Money,
  opts: { date?: Date; clientOpId?: string | null; raiseTarget?: boolean } = {},
  existingTx?: MoneyTx,
) {
  return withMoneyLock(userId, async (tx) => {
    if (opts.clientOpId) {
      const replay = await tx.budgetAllocation.findFirst({
        where: { userId, clientOpId: opts.clientOpId },
      });
      if (replay) return { groupId: replay.groupId ?? '' };
    }

    const amount = money(amountInput);
    if (amount.lte(0)) throw new BadRequestError('An amount has to be greater than zero.');

    const from = await ownedBudget(tx, userId, fromBudgetId);
    const to = await ownedBudget(tx, userId, toBudgetId);
    if (from.id === to.id) throw new BadRequestError('Pick two different plans.');
    if (from.currency !== to.currency) {
      throw new BadRequestError(
        `"${from.name}" is in ${from.currency} and "${to.name}" is in ${to.currency}.`,
      );
    }
    if (to.state === BudgetState.CLOSED) {
      throw new BadRequestError(`"${to.name}" is closed. Reopen it before moving money in.`);
    }

    const snap = await loadSnapshot(userId, {}, tx);
    const groupId = randomUUID();
    const date = opts.date ?? new Date();

    // The receiving plan may be too small to hold it. Raising it is the honest
    // outcome of choosing to move the money there.
    const funded = await fundedThisCycle(tx, to);
    const room = Prisma.Decimal.max(ZERO, to.plannedAmount.sub(funded));
    if (amount.gt(room)) {
      if (!opts.raiseTarget) {
        throw new BadRequestError(
          `"${to.name}" can only take ${room.toFixed(2)} ${to.currency} more before hitting its planned ${to.plannedAmount.toFixed(2)}. Raise the plan to move the full amount.`,
        );
      }
      const raise = amount.sub(room);
      await tx.budgetAdjustment.create({
        data: {
          userId,
          budgetId: to.id,
          amount: raise,
          cycleIndex: to.cycleIndex,
          reason: `Raised to take money moved from ${from.name}`,
          automatic: true,
          groupId,
          date,
        },
      });
      await tx.budget.update({
        where: { id: to.id },
        data: { plannedAmount: to.plannedAmount.add(raise) },
      });
    }

    await moveBetweenPlans(tx, userId, from, to, amount, groupId, date, snap.held);

    if (opts.clientOpId) {
      // Stamp the op id on one half so a replay is recognised.
      const first = await tx.budgetAllocation.findFirst({
        where: { userId, groupId },
        orderBy: { createdAt: 'asc' },
      });
      if (first) {
        await tx.budgetAllocation.update({
          where: { id: first.id },
          data: { clientOpId: opts.clientOpId },
        });
      }
    }

    await assertSound(tx, userId, 'That move would not add up:');
    return { groupId };
  }, existingTx);
}

/**
 * Move a plan's reservation from one wallet to another, without touching the plan.
 *
 * The case this exists for: you move your cash from one wallet to the other, and
 * the envelope needs to follow it. There was no way to do that at all - the
 * reservation was pinned to whichever wallet happened to fund it.
 */
export async function moveReservation(
  userId: string,
  budgetId: string,
  fromAccountId: string,
  toAccountId: string,
  amountInput: number | string | Money,
  opts: { date?: Date; clientOpId?: string | null } = {},
  existingTx?: MoneyTx,
) {
  return withMoneyLock(userId, async (tx) => {
    if (opts.clientOpId) {
      const replay = await tx.budgetAllocation.findFirst({
        where: { userId, clientOpId: opts.clientOpId },
      });
      if (replay) return { groupId: replay.groupId ?? '' };
    }

    const amount = money(amountInput);
    if (amount.lte(0)) throw new BadRequestError('An amount has to be greater than zero.');
    if (fromAccountId === toAccountId) throw new BadRequestError('Pick two different wallets.');

    const budget = await ownedBudget(tx, userId, budgetId);
    const from = await ownedAccount(tx, userId, fromAccountId);
    const to = await ownedAccount(tx, userId, toAccountId);
    assertOpenForWrites(to);
    if (to.currency !== budget.currency) {
      throw new BadRequestError(
        `"${to.name}" holds ${to.currency}; "${budget.name}" is in ${budget.currency}.`,
      );
    }

    const snap = await loadSnapshot(userId, {}, tx);
    const heldThere = snap.held.get(`${from.id} ${budget.id}`) ?? ZERO;
    if (amount.gt(heldThere)) {
      throw new BadRequestError(
        `"${budget.name}" only holds ${heldThere.toFixed(2)} ${budget.currency} in "${from.name}".`,
      );
    }
    const freeThere = snap.available.get(to.id) ?? ZERO;
    if (amount.gt(freeThere)) {
      throw new BadRequestError(
        `"${to.name}" has ${freeThere.toFixed(2)} ${to.currency} free, so it cannot hold ${amount.toFixed(2)} for this plan. Move the cash across first.`,
      );
    }

    const groupId = randomUUID();
    const date = opts.date ?? new Date();
    await tx.budgetAllocation.createMany({
      data: [
        {
          userId,
          budgetId: budget.id,
          accountId: from.id,
          kind: BudgetAllocationKind.RELEASE,
          amount: amount.neg(),
          cycleIndex: budget.cycleIndex,
          date,
          groupId,
          clientOpId: opts.clientOpId ?? null,
          note: `Moved to ${to.name}`,
        },
        {
          userId,
          budgetId: budget.id,
          accountId: to.id,
          kind: BudgetAllocationKind.FUND,
          amount,
          cycleIndex: budget.cycleIndex,
          date,
          groupId,
          note: `Moved from ${from.name}`,
        },
      ],
    });

    await assertSound(tx, userId, 'That move would not add up:');
    return { groupId };
  }, existingTx);
}

// ---------------------------------------------------------------------------
// Plan amounts
// ---------------------------------------------------------------------------

/** Everything in the pot this cycle: carried over plus filled since. */
export async function fundedThisCycle(tx: MoneyTx, budget: Budget): Promise<Money> {
  const [allocAll, allocCycle, spentAll, spentCycle] = await Promise.all([
    tx.budgetAllocation.aggregate({ where: { budgetId: budget.id }, _sum: { amount: true } }),
    tx.budgetAllocation.aggregate({
      where: { budgetId: budget.id, cycleIndex: budget.cycleIndex },
      _sum: { amount: true },
    }),
    tx.transaction.aggregate({
      where: { budgetId: budget.id, kind: TxKind.EXPENSE },
      _sum: { amount: true },
    }),
    tx.transaction.aggregate({
      where: { budgetId: budget.id, kind: TxKind.EXPENSE, budgetCycle: budget.cycleIndex },
      _sum: { amount: true },
    }),
  ]);

  const allocated = allocAll._sum.amount ?? ZERO;
  const allocatedNow = allocCycle._sum.amount ?? ZERO;
  const spent = spentAll._sum.amount ?? ZERO;
  const spentNow = spentCycle._sum.amount ?? ZERO;
  const carriedIn = allocated.sub(allocatedNow).sub(spent.sub(spentNow));
  return carriedIn.add(allocatedNow);
}

/** Raise or cut what a plan is meant to hold, kept as a movement, not an edit. */
export async function adjustPlan(
  userId: string,
  budgetId: string,
  delta: Money,
  opts: { reason?: string | null; date?: Date; clientOpId?: string | null } = {},
  existingTx?: MoneyTx,
) {
  return withMoneyLock(userId, async (tx) => {
    if (opts.clientOpId) {
      const replay = await tx.budgetAdjustment.findFirst({
        where: { userId, clientOpId: opts.clientOpId },
      });
      if (replay) return replay;
    }

    const budget = await ownedBudget(tx, userId, budgetId);
    if (budget.state === BudgetState.CLOSED) {
      throw new BadRequestError('This plan is closed. Reopen it before changing its amount.');
    }

    const next = budget.plannedAmount.add(delta);
    if (next.lte(0)) {
      throw new BadRequestError(
        `That would take "${budget.name}" to ${next.toFixed(2)} ${budget.currency}. A plan has to be worth something - close it instead.`,
      );
    }

    const funded = await fundedThisCycle(tx, budget);
    if (next.lt(funded)) {
      throw new BadRequestError(
        `"${budget.name}" already holds ${funded.toFixed(2)} ${budget.currency}. Give some back before cutting it to ${next.toFixed(2)}.`,
      );
    }

    const created = await tx.budgetAdjustment.create({
      data: {
        userId,
        budgetId: budget.id,
        amount: delta,
        cycleIndex: budget.cycleIndex,
        reason: opts.reason ?? null,
        date: opts.date ?? new Date(),
        clientOpId: opts.clientOpId ?? null,
      },
    });
    await tx.budget.update({ where: { id: budget.id }, data: { plannedAmount: next } });
    return created;
  }, existingTx);
}

// ---------------------------------------------------------------------------
// Development assertion
// ---------------------------------------------------------------------------

/**
 * In development every request ends with a proof that the books still balance,
 * so a regression surfaces at the write that caused it rather than as a wrong
 * number on a screen three days later.
 */
export const ASSERT_AFTER_WRITE = env.NODE_ENV === 'development';
