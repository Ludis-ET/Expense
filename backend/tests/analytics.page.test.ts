import { describe, expect, it } from 'vitest';
import { Prisma } from '../src/core/prisma.js';
import { monthlyEquivalent } from '../src/modules/analytics/analytics.page.js';

const dec = (n: number) => new Prisma.Decimal(n);
const round = (d: Prisma.Decimal) => Number(d.toFixed(2));

describe('monthlyEquivalent', () => {
  it('passes a monthly rule straight through', () => {
    expect(round(monthlyEquivalent(dec(1200), 'MONTHLY', 1))).toBe(1200);
  });

  it('spreads a yearly rule over twelve months', () => {
    expect(round(monthlyEquivalent(dec(1200), 'YEARLY', 1))).toBe(100);
  });

  it('counts a weekly rule as ~4.35 payments', () => {
    expect(round(monthlyEquivalent(dec(100), 'WEEKLY', 1))).toBeCloseTo(434.82, 1);
  });

  // The bug this function exists to avoid: "every 2 weeks" is half of weekly,
  // not the same as weekly, and getting it wrong doubles the fixed-cost floor.
  it('halves a fortnightly rule rather than treating it as weekly', () => {
    const weekly = monthlyEquivalent(dec(100), 'WEEKLY', 1);
    const fortnightly = monthlyEquivalent(dec(100), 'WEEKLY', 2);
    expect(round(fortnightly)).toBeCloseTo(round(weekly) / 2, 1);
  });

  it('divides by the interval for every frequency', () => {
    expect(round(monthlyEquivalent(dec(600), 'MONTHLY', 3))).toBe(200);
    expect(round(monthlyEquivalent(dec(2400), 'YEARLY', 2))).toBe(100);
    expect(round(monthlyEquivalent(dec(30), 'DAILY', 30))).toBeCloseTo(30.44, 1);
  });

  it('treats a nonsense interval as every-one rather than dividing by zero', () => {
    expect(round(monthlyEquivalent(dec(500), 'MONTHLY', 0))).toBe(500);
  });
});
