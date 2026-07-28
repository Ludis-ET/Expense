import { describe, expect, it } from 'vitest';
import { BudgetPeriod } from '../generated/client/index.js';
import { addPeriod, cycleLabel } from '../src/modules/budgets/budgets.periods.js';

const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d, 9));
const day = (d: Date) => d.toISOString().slice(0, 10);

describe('addPeriod', () => {
  it('advances a week', () => {
    expect(day(addPeriod(BudgetPeriod.WEEKLY, utc(2026, 7, 1)))).toBe('2026-07-08');
  });

  it('advances a month keeping the day', () => {
    expect(day(addPeriod(BudgetPeriod.MONTHLY, utc(2026, 7, 15)))).toBe('2026-08-15');
  });

  it('clamps a month-end day into a shorter month', () => {
    // 31 Jan + 1 month must land on 28 Feb, not spill into March.
    expect(day(addPeriod(BudgetPeriod.MONTHLY, utc(2026, 1, 31)))).toBe('2026-02-28');
  });

  it('does not drift after clamping', () => {
    // The anchor day is re-read from the clamped date, so Feb 28 -> Mar 28.
    const feb = addPeriod(BudgetPeriod.MONTHLY, utc(2026, 1, 31));
    expect(day(addPeriod(BudgetPeriod.MONTHLY, feb))).toBe('2026-03-28');
  });

  it('advances a quarter', () => {
    expect(day(addPeriod(BudgetPeriod.QUARTERLY, utc(2026, 7, 10)))).toBe('2026-10-10');
  });

  it('advances a year', () => {
    expect(day(addPeriod(BudgetPeriod.YEARLY, utc(2026, 7, 10)))).toBe('2027-07-10');
  });

  it('handles a leap day rolling forward a year', () => {
    expect(day(addPeriod(BudgetPeriod.YEARLY, utc(2028, 2, 29)))).toBe('2029-02-28');
  });

  it('preserves the time of day so cycles roll at a stable hour', () => {
    const next = addPeriod(BudgetPeriod.MONTHLY, utc(2026, 7, 15));
    expect(next.getUTCHours()).toBe(9);
  });
});

describe('cycleLabel', () => {
  it('names a monthly cycle by its month', () => {
    expect(cycleLabel(BudgetPeriod.MONTHLY, utc(2026, 7, 1), utc(2026, 8, 1))).toBe('July 2026');
  });

  it('names a yearly cycle by its span', () => {
    expect(cycleLabel(BudgetPeriod.YEARLY, utc(2026, 1, 1), utc(2027, 1, 1))).toBe('2026–2027');
  });

  it('names a weekly cycle by its inclusive day range', () => {
    expect(cycleLabel(BudgetPeriod.WEEKLY, utc(2026, 7, 1), utc(2026, 7, 8))).toBe('01 Jul – 07 Jul');
  });

  it('falls back to a day range for a one-time plan with no period', () => {
    expect(cycleLabel(null, utc(2026, 7, 1), utc(2026, 7, 5))).toBe('01 Jul – 04 Jul');
  });
});
