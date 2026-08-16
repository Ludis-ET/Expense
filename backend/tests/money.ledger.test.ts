/**
 * The money rules, asserted directly.
 *
 * These are the twelve scenarios that were broken before the money core existed,
 * written as tests, plus a property test that plays random sequences of
 * operations and checks the books still balance. The property test is the one
 * that matters most: B1, B9 and B11 were all cases nobody would have thought to
 * write a case for.
 */
import { describe, expect, it } from 'vitest';
import { Prisma } from '../generated/client/index.js';
import {
  ZERO,
  availableByAccount,
  checkInvariants,
  heldByAccount,
  heldByPair,
  pairKey,
  potByBudget,
  readyToAssign,
  realBalances,
  sharesOfBudget,
  snapshot,
  splitPair,
  type AccountSeed,
  type CashRow,
  type HoldRow,
  type PlanSpendRow,
} from '../src/core/money/ledger.js';

const d = (v: number | string) => new Prisma.Decimal(v);

const wallet = (id: string, opening: number, currency = 'ETB'): AccountSeed => ({
  id,
  currency,
  openingBalance: d(opening),
  archived: false,
});

const income = (accountId: string, amount: number): CashRow => ({
  accountId,
  kind: 'INCOME',
  amount: d(amount),
});

const expense = (accountId: string, amount: number): CashRow => ({
  accountId,
  kind: 'EXPENSE',
  amount: d(amount),
});

const transfer = (from: string, to: string, amount: number, received?: number): CashRow => ({
  accountId: from,
  kind: 'TRANSFER',
  amount: d(amount),
  transferAccountId: to,
  transferAmount: received !== undefined ? d(received) : null,
});

const hold = (accountId: string, budgetId: string, amount: number): HoldRow => ({
  accountId,
  budgetId,
  amount: d(amount),
});

const planSpend = (budgetId: string, sourceId: string, amount: number): PlanSpendRow => ({
  budgetId,
  budgetSourceAccountId: sourceId,
  amount: d(amount),
});

// ---------------------------------------------------------------------------
// I1 - cash conservation
// ---------------------------------------------------------------------------

describe('real balances', () => {
  it('adds income and subtracts spending', () => {
    const real = realBalances([wallet('cash', 100)], [income('cash', 500), expense('cash', 120)]);
    expect(real.get('cash')!.toFixed(2)).toBe('480.00');
  });

  it('moves money between wallets without creating any', () => {
    const real = realBalances(
      [wallet('cbe', 1000), wallet('cash', 0)],
      [transfer('cbe', 'cash', 300)],
    );
    expect(real.get('cbe')!.toFixed(2)).toBe('700.00');
    expect(real.get('cash')!.toFixed(2)).toBe('300.00');
    expect(real.get('cbe')!.add(real.get('cash')!).toFixed(2)).toBe('1000.00');
  });

  it('credits the destination what actually arrived across a currency', () => {
    // 100 USD out, 5,650 ETB in. Crediting 100 ETB - the old behaviour - would
    // have destroyed 5,550 birr on the way across.
    const real = realBalances(
      [wallet('usd', 500, 'USD'), wallet('etb', 0, 'ETB')],
      [transfer('usd', 'etb', 100, 5650)],
    );
    expect(real.get('usd')!.toFixed(2)).toBe('400.00');
    expect(real.get('etb')!.toFixed(2)).toBe('5650.00');
  });

  it('ignores rows against wallets it was not given', () => {
    const real = realBalances([wallet('cash', 50)], [income('someone-elses', 999)]);
    expect(real.get('cash')!.toFixed(2)).toBe('50.00');
    expect(real.has('someone-elses')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// I2 / I4 - reservations and pots
// ---------------------------------------------------------------------------

describe('reservations', () => {
  it('holds money per wallet and per plan', () => {
    const held = heldByPair(
      [hold('cbe', 'rent', 3000), hold('cash', 'food', 500)],
      [planSpend('food', 'cash', 200)],
    );
    expect(held.get(pairKey('cbe', 'rent'))!.toFixed(2)).toBe('3000.00');
    expect(held.get(pairKey('cash', 'food'))!.toFixed(2)).toBe('300.00');
  });

  it('drops a pair that nets to nothing', () => {
    // A plan funded from a wallet and fully given back holds nothing there, and
    // should not linger as a row that blocks deleting the wallet.
    const held = heldByPair([hold('cash', 'food', 500), hold('cash', 'food', -500)], []);
    expect(held.has(pairKey('cash', 'food'))).toBe(false);
  });

  it('makes a pot exactly the sum of its wallets', () => {
    const held = heldByPair([hold('cbe', 'trip', 2000), hold('cash', 'trip', 500)], []);
    expect(potByBudget(held).get('trip')!.toFixed(2)).toBe('2500.00');
  });

  it('frees the reservation of the wallet that held it, not the one that paid', () => {
    // Plan funded from CBE, paid in cash. CBE's reservation is what comes off.
    const held = heldByPair([hold('cbe', 'rent', 3000)], [planSpend('rent', 'cbe', 1000)]);
    expect(held.get(pairKey('cbe', 'rent'))!.toFixed(2)).toBe('2000.00');
  });

  it('splitPair recovers wallet and plan from held keys (not space-split)', () => {
    // accounts.reservations used to split on space and always returned [].
    const key = pairKey('acc-wallet', 'bud-rent');
    expect(key.includes(' ')).toBe(false);
    expect(key.split(' ')[0]).not.toBe('acc-wallet');
    const { accountId, budgetId } = splitPair(key);
    expect(accountId).toBe('acc-wallet');
    expect(budgetId).toBe('bud-rent');

    const held = heldByPair([hold('acc-wallet', 'bud-rent', 500)], []);
    const rows: Array<{ budgetId: string; amount: ReturnType<typeof d> }> = [];
    for (const [k, amount] of held) {
      const parts = splitPair(k);
      if (parts.accountId === 'acc-wallet' && amount.gt(0)) {
        rows.push({ budgetId: parts.budgetId, amount });
      }
    }
    expect(rows).toHaveLength(1);
    expect(rows[0]!.budgetId).toBe('bud-rent');
    expect(rows[0]!.amount.toFixed(2)).toBe('500.00');
  });
});

// ---------------------------------------------------------------------------
// I3 / I5 - solvency
// ---------------------------------------------------------------------------

describe('availability', () => {
  it('subtracts what plans have spoken for', () => {
    const real = realBalances([wallet('cbe', 5000)], []);
    const held = heldByAccount(heldByPair([hold('cbe', 'rent', 3000)], []));
    expect(availableByAccount(real, held).get('cbe')!.toFixed(2)).toBe('2000.00');
  });

  it('counts only free, unarchived money in the right currency as ready to assign', () => {
    const accounts = [wallet('cbe', 5000), wallet('usd', 200, 'USD'), { ...wallet('old', 900), archived: true }];
    const real = realBalances(accounts, []);
    const held = heldByAccount(heldByPair([hold('cbe', 'rent', 3000)], []));
    expect(readyToAssign(accounts, real, held, 'ETB').toFixed(2)).toBe('2000.00');
    expect(readyToAssign(accounts, real, held, 'USD').toFixed(2)).toBe('200.00');
  });
});

// ---------------------------------------------------------------------------
// The scenarios that were broken
// ---------------------------------------------------------------------------

describe('the failures this model exists to prevent', () => {
  it('B1: deleting the income that funded a plan is caught, not absorbed', () => {
    // Earn 1,000, reserve all of it, then remove the income.
    const snap = snapshot([wallet('cash', 0)], [], [hold('cash', 'rent', 1000)], []);
    const problems = checkInvariants(snap);

    expect(problems.map((p) => p.code)).toContain('I3');
    expect(problems.map((p) => p.code)).toContain('I5');
    // And crucially it is *reported*, not clamped away to zero the way
    // lockedByAccount used to with Decimal.max(0, v).
    expect(snap.heldPerAccount.get('cash')!.toFixed(2)).toBe('1000.00');
    expect(snap.available.get('cash')!.toFixed(2)).toBe('-1000.00');
  });

  it('B9: a plan spend always frees a reservation, so a pot cannot outlive its wallets', () => {
    const snap = snapshot(
      [wallet('cbe', 5000)],
      [expense('cbe', 1000)],
      [hold('cbe', 'rent', 3000)],
      [planSpend('rent', 'cbe', 1000)],
    );
    expect(snap.pots.get('rent')!.toFixed(2)).toBe('2000.00');
    expect(snap.heldPerAccount.get('cbe')!.toFixed(2)).toBe('2000.00');
    expect(checkInvariants(snap)).toEqual([]);
  });

  it('B10: releasing more than a wallet holds shows up as a negative reservation', () => {
    const snap = snapshot([wallet('cash', 1000)], [], [hold('cash', 'food', 200), hold('cash', 'food', -500)], []);
    const problems = checkInvariants(snap);
    expect(problems.some((p) => p.code === 'I2')).toBe(true);
  });

  it('B23: money one wallet fronts for another is conserved overall', () => {
    // Rent funded from CBE, paid in cash. Cash is down, CBE has that much more
    // free - and the totals still add up, which is what makes it honest rather
    // than money quietly appearing somewhere.
    const before = snapshot(
      [wallet('cbe', 5000), wallet('cash', 1000)],
      [],
      [hold('cbe', 'rent', 3000)],
      [],
    );
    const after = snapshot(
      [wallet('cbe', 5000), wallet('cash', 1000)],
      [expense('cash', 1000)],
      [hold('cbe', 'rent', 3000)],
      [planSpend('rent', 'cbe', 1000)],
    );

    const freeBefore = [...before.available.values()].reduce((s, v) => s.add(v), ZERO);
    const freeAfter = [...after.available.values()].reduce((s, v) => s.add(v), ZERO);
    // A thousand birr genuinely left, so free money is unchanged: the spend came
    // out of money that was already reserved for it.
    expect(freeAfter.toFixed(2)).toBe(freeBefore.toFixed(2));
    expect(after.available.get('cash')!.toFixed(2)).toBe('0.00');
    expect(after.available.get('cbe')!.toFixed(2)).toBe('3000.00');
    expect(checkInvariants(after)).toEqual([]);
  });

  it('reports which wallets a plan is held in, largest first', () => {
    const held = heldByPair(
      [hold('cash', 'trip', 500), hold('cbe', 'trip', 2000), hold('telebirr', 'trip', 1200)],
      [],
    );
    expect(sharesOfBudget(held, 'trip').map((s) => s.accountId)).toEqual(['cbe', 'telebirr', 'cash']);
  });

  it('a healthy ledger reports nothing', () => {
    const snap = snapshot(
      [wallet('cbe', 5000), wallet('cash', 800)],
      [income('cbe', 2000), expense('cash', 300), transfer('cbe', 'cash', 500)],
      [hold('cbe', 'rent', 3000), hold('cash', 'food', 400)],
      [planSpend('food', 'cash', 150)],
    );
    expect(checkInvariants(snap)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Property test
// ---------------------------------------------------------------------------

/**
 * Random sequences of legal operations must never break the books.
 *
 * "Legal" is doing the work here: each step only does what the posting core
 * would allow - never reserving more than a wallet has free, never spending more
 * than a pot holds. If the invariants can be broken by a sequence of individually
 * permitted moves, the model is wrong, and that is exactly the class of bug that
 * survived in this codebase for months.
 */
describe('random sequences of legal operations', () => {
  const seedRandom = (seed: number) => {
    let state = seed;
    return () => {
      state = (state * 1_103_515_245 + 12_345) % 2_147_483_648;
      return state / 2_147_483_648;
    };
  };

  it('never breaks an invariant over 200 runs', () => {
    for (let run = 0; run < 200; run += 1) {
      const rand = seedRandom(run + 1);
      const accounts = [wallet('a', 1000), wallet('b', 500)];
      const cash: CashRow[] = [];
      const holds: HoldRow[] = [];
      const spends: PlanSpendRow[] = [];
      const plans = ['p1', 'p2'];

      for (let step = 0; step < 40; step += 1) {
        const snap = snapshot(accounts, cash, holds, spends);
        const pick = Math.floor(rand() * 5);
        const account = accounts[Math.floor(rand() * accounts.length)]!;
        const plan = plans[Math.floor(rand() * plans.length)]!;
        const free = snap.available.get(account.id) ?? ZERO;
        const pot = snap.pots.get(plan) ?? ZERO;
        const heldHere = snap.held.get(pairKey(account.id, plan)) ?? ZERO;
        const real = snap.real.get(account.id) ?? ZERO;

        // Amounts are always a fraction of what is genuinely permitted, so every
        // step is one the posting core would have accepted.
        const slice = (cap: Prisma.Decimal) => cap.mul(Math.floor(rand() * 60) / 100).toDecimalPlaces(2);

        if (pick === 0) {
          cash.push(income(account.id, Math.floor(rand() * 400) + 1));
        } else if (pick === 1 && free.gt(0)) {
          const amount = slice(free);
          if (amount.gt(0)) cash.push(expense(account.id, Number(amount)));
        } else if (pick === 2 && free.gt(0)) {
          const amount = slice(free);
          if (amount.gt(0)) holds.push(hold(account.id, plan, Number(amount)));
        } else if (pick === 3 && heldHere.gt(0)) {
          // Spending out of the pot: capped by the wallet's share and by the cash
          // actually in the wallet paying.
          const amount = slice(Prisma.Decimal.min(heldHere, real));
          if (amount.gt(0)) {
            cash.push(expense(account.id, Number(amount)));
            spends.push(planSpend(plan, account.id, Number(amount)));
          }
        } else if (pick === 4 && heldHere.gt(0)) {
          const amount = slice(heldHere);
          if (amount.gt(0)) holds.push(hold(account.id, plan, -Number(amount)));
        }

        const problems = checkInvariants(snapshot(accounts, cash, holds, spends));
        expect(
          problems,
          `run ${run} step ${step}: ${problems.map((p) => p.message).join('; ')}`,
        ).toEqual([]);
        void pot;
      }
    }
  });
});
