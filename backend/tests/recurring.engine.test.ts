import { describe, expect, it } from 'vitest';
import { Frequency } from '@prisma/client';
import { advanceNextRun } from '../src/modules/recurring/recurring.engine.js';

const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d, 9));

describe('advanceNextRun', () => {
  it('advances daily by interval', () => {
    const next = advanceNextRun(
      { frequency: Frequency.DAILY, interval: 3, dayOfMonth: null },
      utc(2026, 7, 1),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2026-07-04');
  });

  it('advances weekly by interval', () => {
    const next = advanceNextRun(
      { frequency: Frequency.WEEKLY, interval: 2, dayOfMonth: null },
      utc(2026, 7, 1),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2026-07-15');
  });

  it('advances monthly keeping the day', () => {
    const next = advanceNextRun(
      { frequency: Frequency.MONTHLY, interval: 1, dayOfMonth: 15 },
      utc(2026, 7, 15),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2026-08-15');
  });

  it('clamps day 31 to shorter months', () => {
    const next = advanceNextRun(
      { frequency: Frequency.MONTHLY, interval: 1, dayOfMonth: 31 },
      utc(2026, 1, 31),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2026-02-28'); // 2026 is not a leap year
  });

  it('clamps day 31 to Feb 29 in a leap year', () => {
    const next = advanceNextRun(
      { frequency: Frequency.MONTHLY, interval: 1, dayOfMonth: 31 },
      utc(2028, 1, 31),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2028-02-29');
  });

  it('returns to day 31 after a clamped month', () => {
    const next = advanceNextRun(
      { frequency: Frequency.MONTHLY, interval: 1, dayOfMonth: 31 },
      utc(2026, 2, 28),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2026-03-31');
  });

  it('advances yearly', () => {
    const next = advanceNextRun(
      { frequency: Frequency.YEARLY, interval: 1, dayOfMonth: null },
      utc(2026, 9, 11),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2027-09-11');
  });

  it('advances monthly across a year boundary', () => {
    const next = advanceNextRun(
      { frequency: Frequency.MONTHLY, interval: 2, dayOfMonth: 1 },
      utc(2026, 12, 1),
    );
    expect(next.toISOString().slice(0, 10)).toBe('2027-02-01');
  });
});
