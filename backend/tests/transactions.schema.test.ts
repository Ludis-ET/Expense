import { describe, expect, it } from 'vitest';
import {
  createTransactionSchema,
  listTransactionsQuery,
} from '../src/modules/transactions/transactions.schema.js';

const base = {
  amount: 100,
  date: '2026-07-01',
  accountId: 'acc1',
};

describe('createTransactionSchema', () => {
  it('accepts an expense with a category', () => {
    const parsed = createTransactionSchema.parse({ ...base, kind: 'EXPENSE', categoryId: 'cat1' });
    expect(parsed.kind).toBe('EXPENSE');
    expect(parsed.currency).toBe('ETB'); // default
    expect(parsed.tags).toEqual([]); // default
  });

  it('rejects an expense without a category', () => {
    const result = createTransactionSchema.safeParse({ ...base, kind: 'EXPENSE' });
    expect(result.success).toBe(false);
  });

  it('rejects an income without a category', () => {
    const result = createTransactionSchema.safeParse({ ...base, kind: 'INCOME' });
    expect(result.success).toBe(false);
  });

  it('accepts a transfer to a different account', () => {
    const parsed = createTransactionSchema.parse({
      ...base,
      kind: 'TRANSFER',
      transferAccountId: 'acc2',
    });
    expect(parsed.kind).toBe('TRANSFER');
  });

  it('rejects a transfer to the same account', () => {
    const result = createTransactionSchema.safeParse({
      ...base,
      kind: 'TRANSFER',
      transferAccountId: 'acc1',
    });
    expect(result.success).toBe(false);
  });

  it('rejects a non-positive amount', () => {
    const result = createTransactionSchema.safeParse({
      ...base,
      kind: 'EXPENSE',
      categoryId: 'cat1',
      amount: 0,
    });
    expect(result.success).toBe(false);
  });

  it('coerces a string amount', () => {
    const parsed = createTransactionSchema.parse({
      ...base,
      kind: 'EXPENSE',
      categoryId: 'cat1',
      amount: '250.50',
    });
    expect(parsed.amount).toBe(250.5);
  });
});

describe('listTransactionsQuery', () => {
  it('applies defaults', () => {
    const parsed = listTransactionsQuery.parse({});
    expect(parsed.page).toBe(1);
    expect(parsed.pageSize).toBe(25);
    expect(parsed.sort).toBe('date_desc');
  });

  it('coerces numeric strings from the query string', () => {
    const parsed = listTransactionsQuery.parse({ page: '3', pageSize: '50', min: '10' });
    expect(parsed.page).toBe(3);
    expect(parsed.pageSize).toBe(50);
    expect(parsed.min).toBe(10);
  });

  it('caps pageSize at 100', () => {
    expect(listTransactionsQuery.safeParse({ pageSize: '500' }).success).toBe(false);
  });

  it('coerces date filters', () => {
    const parsed = listTransactionsQuery.parse({ from: '2026-06-01', to: '2026-06-30' });
    expect(parsed.from).toBeInstanceOf(Date);
    expect(parsed.to).toBeInstanceOf(Date);
  });
});
