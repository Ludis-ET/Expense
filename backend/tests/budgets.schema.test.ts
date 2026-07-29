import { describe, expect, it } from 'vitest';
import {
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

  it('accepts a budgetId instead of an accountId', () => {
    const parsed = createTransactionSchema.parse({ kind: 'EXPENSE', ...base, budgetId: 'b1' });
    expect(parsed.kind === 'EXPENSE' && parsed.budgetId).toBe('b1');
    expect(parsed.accountId).toBeUndefined();
  });

  it('still accepts a plain account expense', () => {
    const parsed = createTransactionSchema.parse({ kind: 'EXPENSE', ...base, accountId: 'a1' });
    expect(parsed.accountId).toBe('a1');
  });

  it('rejects an expense with neither an account nor a plan', () => {
    expect(createTransactionSchema.safeParse({ kind: 'EXPENSE', ...base }).success).toBe(false);
  });

  it('income must still name an account - plans only pay expenses', () => {
    expect(
      createTransactionSchema.safeParse({ kind: 'INCOME', ...base, budgetId: 'b1' }).success,
    ).toBe(false);
  });
});
