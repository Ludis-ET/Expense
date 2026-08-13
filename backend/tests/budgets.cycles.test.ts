/**
 * Which cycle a plan expense belongs to.
 *
 * The old code stamped whichever cycle happened to be open when the row was
 * written, so a receipt typed up on the 2nd for a purchase made on the 30th
 * landed in the wrong month - permanently, in a snapshot that is never
 * recomputed. A phone syncing three days late did it to every queued expense.
 */
import { describe, expect, it } from 'vitest';
import { RecurrenceUnit } from '../generated/client/index.js';
import { cycleIndexForDate, subRecurrence } from '../src/modules/budgets/budgets.periods.js';

const utc = (y: number, m: number, day: number) => new Date(Date.UTC(y, m - 1, day));

const monthly = {
  kind: 'RECURRING' as const,
  cycleIndex: 3,
  cycleStartedAt: utc(2026, 8, 1),
  nextResetAt: utc(2026, 9, 1),
  recurrenceUnit: RecurrenceUnit.MONTH,
  recurrenceInterval: 1,
};

const pastCycles = [
  { index: 0, startedAt: utc(2026, 5, 1), endedAt: utc(2026, 6, 1) },
  { index: 1, startedAt: utc(2026, 6, 1), endedAt: utc(2026, 7, 1) },
  { index: 2, startedAt: utc(2026, 7, 1), endedAt: utc(2026, 8, 1) },
];

describe('cycleIndexForDate', () => {
  it('puts a date inside the open cycle in the open cycle', () => {
    expect(cycleIndexForDate(monthly, utc(2026, 8, 14), pastCycles)).toBe(3);
  });

  it('back-dates into the cycle the date actually falls in', () => {
    expect(cycleIndexForDate(monthly, utc(2026, 7, 30), pastCycles)).toBe(2);
    expect(cycleIndexForDate(monthly, utc(2026, 6, 15), pastCycles)).toBe(1);
    expect(cycleIndexForDate(monthly, utc(2026, 5, 2), pastCycles)).toBe(0);
  });

  it('projects forward for a date past the current cycle', () => {
    // Cycle 3 is August. September is 4, October 5 - so a plan that has not
    // rolled yet still files a future-dated expense in the right cycle rather
    // than inflating the open one.
    expect(cycleIndexForDate(monthly, utc(2026, 9, 5), pastCycles)).toBe(4);
    expect(cycleIndexForDate(monthly, utc(2026, 10, 5), pastCycles)).toBe(5);
  });

  it('never goes below zero for a date older than the plan', () => {
    expect(cycleIndexForDate(monthly, utc(2020, 1, 1), pastCycles)).toBe(0);
  });

  it('walks back through cycles that were never snapshotted', () => {
    // Quiet cycles are skipped rather than recorded, so the lookup has to work
    // without them - an hourly plan left dormant has thousands.
    expect(cycleIndexForDate(monthly, utc(2026, 7, 10), [])).toBe(2);
    expect(cycleIndexForDate(monthly, utc(2026, 6, 10), [])).toBe(1);
  });

  it('gives a one-time plan a single cycle whatever the date', () => {
    const oneTime = { ...monthly, kind: 'ONE_TIME' as const, recurrenceUnit: null };
    expect(cycleIndexForDate(oneTime, utc(2020, 1, 1), [])).toBe(0);
    expect(cycleIndexForDate(oneTime, utc(2030, 1, 1), [])).toBe(0);
  });
});

describe('subRecurrence', () => {
  it('mirrors addRecurrence for each unit', () => {
    expect(subRecurrence(RecurrenceUnit.DAY, 3, utc(2026, 8, 10)).toISOString().slice(0, 10)).toBe('2026-08-07');
    expect(subRecurrence(RecurrenceUnit.WEEK, 2, utc(2026, 8, 15)).toISOString().slice(0, 10)).toBe('2026-08-01');
    expect(subRecurrence(RecurrenceUnit.MONTH, 1, utc(2026, 8, 15)).toISOString().slice(0, 10)).toBe('2026-07-15');
    expect(subRecurrence(RecurrenceUnit.QUARTER, 1, utc(2026, 8, 15)).toISOString().slice(0, 10)).toBe('2026-05-15');
    expect(subRecurrence(RecurrenceUnit.YEAR, 1, utc(2026, 8, 15)).toISOString().slice(0, 10)).toBe('2025-08-15');
  });

  it('clamps into shorter months going backwards', () => {
    expect(subRecurrence(RecurrenceUnit.MONTH, 1, utc(2026, 3, 31)).toISOString().slice(0, 10)).toBe('2026-02-28');
  });
});
