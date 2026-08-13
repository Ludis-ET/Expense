import { describe, expect, it } from 'vitest';
import {
  adjustBudgetSchema,
  createBudgetSchema,
  fundBudgetSchema,
  releaseBudgetSchema,
} from '../src/modules/budgets/budgets.schema.js';
import { createTransactionSchema } from '../src/modules/transactions/transactions.schema.js';

describe('createBudgetSchema', () => {
  it('accepts a one-time plan with no category', () => {
    const parsed = createBudgetSchema.parse({ name: 'New laptop', plannedAmount: 60000 });
    expect(parsed.kind).toBe('ONE_TIME');
    expect(parsed.recurrenceUnit).toBeUndefined();
    expect(parsed.recurrenceInterval).toBe(1);
    expect(parsed.currency).toBe('ETB');
    expect(parsed.alertThreshold).toBe(80);
  });

  it('requires a cadence for a recurring plan', () => {
    const result = createBudgetSchema.safeParse({
      name: 'Groceries',
      kind: 'RECURRING',
      plannedAmount: 5000,
    });
    expect(result.success).toBe(false);
  });

  it('accepts any every-N-units cadence', () => {
    const parsed = createBudgetSchema.parse({
      name: 'Coffee run',
      kind: 'RECURRING',
      recurrenceUnit: 'HOUR',
      recurrenceInterval: 6,
      plannedAmount: 200,
    });
    expect(parsed.recurrenceUnit).toBe('HOUR');
    expect(parsed.recurrenceInterval).toBe(6);
  });

  it('refuses to author the built-in Unplanned kind', () => {
    const result = createBudgetSchema.safeParse({
      name: 'Sneaky',
      kind: 'UNPLANNED',
      plannedAmount: 10,
    });
    expect(result.success).toBe(false);
  });

  it('takes a user-chosen start date', () => {
    const parsed = createBudgetSchema.parse({
      name: 'School fees',
      plannedAmount: 5000,
      startsAt: '2026-09-01',
    });
    expect(parsed.startsAt?.toISOString().slice(0, 10)).toBe('2026-09-01');
  });

  it('rejects a non-positive planned amount', () => {
    expect(createBudgetSchema.safeParse({ name: 'X', plannedAmount: 0 }).success).toBe(false);
  });

  it('rejects an end date before the start date', () => {
    const result = createBudgetSchema.safeParse({
      name: 'Trip',
      plannedAmount: 100,
      startsAt: '2026-08-01',
      endDate: '2026-07-01',
    });
    expect(result.success).toBe(false);
  });
});

describe('fund / release schemas', () => {
  it('funding needs an account', () => {
    expect(fundBudgetSchema.safeParse({ amount: 100 }).success).toBe(false);
    expect(fundBudgetSchema.safeParse({ accountId: 'acc1', amount: 100 }).success).toBe(true);
  });

  it('releasing defaults to the largest source when no account is given', () => {
    const parsed = releaseBudgetSchema.parse({ amount: 50 });
    expect(parsed.accountId).toBeUndefined();
  });

  it('rejects negative movements in both directions', () => {
    expect(fundBudgetSchema.safeParse({ accountId: 'a', amount: -1 }).success).toBe(false);
    expect(releaseBudgetSchema.safeParse({ amount: -1 }).success).toBe(false);
  });
});

describe('expenses paid from a plan', () => {
  const base = { amount: 100, date: '2026-07-28', categoryId: 'cat1' };

  it('takes a plan alongside the wallet the cash leaves', () => {
    // Every expense names a wallet now, plan or no plan. A plan says which
    // envelope the spend draws down; it never decides where the cash came from,
    // because those are genuinely two different questions - you can pay from
    // cash for something reserved in the bank.
    const parsed = createTransactionSchema.parse({
      kind: 'EXPENSE',
      ...base,
      accountId: 'a1',
      budgetId: 'b1',
    });
    expect(parsed.kind === 'EXPENSE' && parsed.budgetId).toBe('b1');
    expect(parsed.accountId).toBe('a1');
  });

  it('treats an expense with no plan as unplanned', () => {
    const parsed = createTransactionSchema.parse({ kind: 'EXPENSE', ...base, accountId: 'a1' });
    expect(parsed.kind === 'EXPENSE' && parsed.budgetId).toBeUndefined();
  });

  it('rejects an expense that names no wallet', () => {
    expect(
      createTransactionSchema.safeParse({ kind: 'EXPENSE', ...base, budgetId: 'b1' }).success,
    ).toBe(false);
  });

  it('accepts a cover source for a plan that cannot afford the spend', () => {
    const parsed = createTransactionSchema.parse({
      kind: 'EXPENSE',
      ...base,
      accountId: 'a1',
      budgetId: 'b1',
      cover: { from: 'BUDGET', budgetId: 'b2' },
    });
    expect(parsed.kind === 'EXPENSE' && parsed.cover?.from).toBe('BUDGET');
  });
});

describe('adjustBudgetSchema', () => {
  it('takes a direction and a positive amount', () => {
    const parsed = adjustBudgetSchema.parse({ direction: 'ADD', amount: '250' });
    expect(parsed.direction).toBe('ADD');
    expect(parsed.amount).toBe(250);
  });

  it('rejects a signed amount - direction carries the sign', () => {
    expect(adjustBudgetSchema.safeParse({ direction: 'DEDUCT', amount: -250 }).success).toBe(false);
  });

  it('rejects a zero change', () => {
    expect(adjustBudgetSchema.safeParse({ direction: 'ADD', amount: 0 }).success).toBe(false);
  });

  it('needs a direction', () => {
    expect(adjustBudgetSchema.safeParse({ amount: 100 }).success).toBe(false);
  });

  it('keeps an optional reason and date', () => {
    const parsed = adjustBudgetSchema.parse({
      direction: 'DEDUCT',
      amount: 40,
      reason: '  rent dropped  ',
      date: '2026-07-29',
    });
    expect(parsed.reason).toBe('rent dropped');
    expect(parsed.date).toBeInstanceOf(Date);
  });
});
