import { describe, expect, it } from 'vitest';
import {
  createRecurringSchema,
  updateRecurringSchema,
} from '../src/modules/recurring/recurring.schema.js';

const baseExpense = {
  name: 'Netflix',
  kind: 'EXPENSE' as const,
  amount: 400,
  currency: 'ETB',
  accountId: 'acc1',
  categoryId: 'cat1',
  frequency: 'MONTHLY' as const,
  nextRun: '2026-08-01',
};

describe('createRecurringSchema', () => {
  it('requires a plan for expense rules', () => {
    const result = createRecurringSchema.safeParse(baseExpense);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.some((i) => i.path.includes('budgetId'))).toBe(true);
    }
  });

  it('accepts an expense linked to a plan (one-time or recurring)', () => {
    const parsed = createRecurringSchema.parse({
      ...baseExpense,
      budgetId: 'plan1',
    });
    expect(parsed.budgetId).toBe('plan1');
    expect(parsed.kind).toBe('EXPENSE');
  });

  it('rejects income with a plan', () => {
    const result = createRecurringSchema.safeParse({
      ...baseExpense,
      kind: 'INCOME',
      budgetId: 'plan1',
    });
    expect(result.success).toBe(false);
  });

  it('accepts income without a plan', () => {
    const parsed = createRecurringSchema.parse({
      ...baseExpense,
      kind: 'INCOME',
      budgetId: undefined,
    });
    expect(parsed.kind).toBe('INCOME');
    expect(parsed.budgetId ?? null).toBeNull();
  });
});

describe('updateRecurringSchema', () => {
  it('rejects clearing a plan by switching kind to income while keeping budgetId', () => {
    const result = updateRecurringSchema.safeParse({
      kind: 'INCOME',
      budgetId: 'plan1',
    });
    expect(result.success).toBe(false);
  });

  it('allows setting budgetId on an expense patch', () => {
    const parsed = updateRecurringSchema.parse({ budgetId: 'plan2' });
    expect(parsed.budgetId).toBe('plan2');
  });
});
