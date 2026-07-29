import { describe, expect, it } from 'vitest';
import { RecurrenceUnit } from '../generated/client/index.js';
import {
  addRecurrence,
  cycleLabel,
  periodNoun,
  recurrenceLabel,
} from '../src/modules/budgets/budgets.periods.js';

const utc = (y: number, m: number, d: number, h = 9) => new Date(Date.UTC(y, m - 1, d, h));
const day = (d: Date) => d.toISOString().slice(0, 10);
const stamp = (d: Date) => d.toISOString().slice(0, 16);

describe('addRecurrence', () => {
  it('steps by hours', () => {
    expect(stamp(addRecurrence(RecurrenceUnit.HOUR, 6, utc(2026, 7, 1, 9)))).toBe('2026-07-01T15:00');
  });

  it('rolls hours over a day boundary', () => {
    expect(stamp(addRecurrence(RecurrenceUnit.HOUR, 6, utc(2026, 7, 1, 21)))).toBe('2026-07-02T03:00');
  });

  it('steps by days', () => {
    expect(day(addRecurrence(RecurrenceUnit.DAY, 3, utc(2026, 7, 1)))).toBe('2026-07-04');
  });

  it('steps by weeks', () => {
    expect(day(addRecurrence(RecurrenceUnit.WEEK, 2, utc(2026, 7, 1)))).toBe('2026-07-15');
  });

  it('steps by months keeping the day', () => {
    expect(day(addRecurrence(RecurrenceUnit.MONTH, 1, utc(2026, 7, 15)))).toBe('2026-08-15');
  });

  it('clamps a month-end day into a shorter month', () => {
    expect(day(addRecurrence(RecurrenceUnit.MONTH, 1, utc(2026, 1, 31)))).toBe('2026-02-28');
  });

  it('steps by quarters and years', () => {
    expect(day(addRecurrence(RecurrenceUnit.QUARTER, 1, utc(2026, 7, 10)))).toBe('2026-10-10');
    expect(day(addRecurrence(RecurrenceUnit.YEAR, 1, utc(2026, 7, 10)))).toBe('2027-07-10');
  });

  it('handles a leap day rolling forward a year', () => {
    expect(day(addRecurrence(RecurrenceUnit.YEAR, 1, utc(2028, 2, 29)))).toBe('2029-02-28');
  });

  it('treats a zero or negative interval as one step', () => {
    expect(day(addRecurrence(RecurrenceUnit.DAY, 0, utc(2026, 7, 1)))).toBe('2026-07-02');
  });

  it('preserves the time of day so cycles roll at a stable hour', () => {
    expect(addRecurrence(RecurrenceUnit.MONTH, 1, utc(2026, 7, 15)).getUTCHours()).toBe(9);
  });
});

describe('recurrenceLabel', () => {
  it('uses the everyday word for a single step', () => {
    expect(recurrenceLabel(RecurrenceUnit.HOUR, 1)).toBe('hourly');
    expect(recurrenceLabel(RecurrenceUnit.DAY, 1)).toBe('daily');
    expect(recurrenceLabel(RecurrenceUnit.MONTH, 1)).toBe('monthly');
  });

  it('spells out multi-step cadences', () => {
    expect(recurrenceLabel(RecurrenceUnit.HOUR, 6)).toBe('every 6 hours');
    expect(recurrenceLabel(RecurrenceUnit.WEEK, 2)).toBe('every 2 weeks');
  });
});

describe('periodNoun', () => {
  it('names what one cycle is measured in', () => {
    expect(periodNoun(RecurrenceUnit.MONTH, 1)).toBe('month');
    expect(periodNoun(RecurrenceUnit.HOUR, 6)).toBe('6 hours');
  });
});

describe('cycleLabel', () => {
  it('names a whole calendar month', () => {
    expect(cycleLabel(RecurrenceUnit.MONTH, 1, utc(2026, 7, 1), utc(2026, 8, 1))).toBe('July 2026');
  });

  it('falls back to a day range for a mid-month monthly cycle', () => {
    expect(cycleLabel(RecurrenceUnit.MONTH, 1, utc(2026, 7, 15), utc(2026, 8, 15))).toBe(
      '15 Jul – 14 Aug',
    );
  });

  it('names a whole calendar year', () => {
    expect(cycleLabel(RecurrenceUnit.YEAR, 1, utc(2026, 1, 1), utc(2027, 1, 1))).toBe('2026');
  });

  it('includes clock time for hourly cycles', () => {
    expect(cycleLabel(RecurrenceUnit.HOUR, 6, utc(2026, 7, 1, 6), utc(2026, 7, 1, 12))).toBe(
      '01 Jul, 06:00 – 01 Jul, 12:00',
    );
  });

  it('collapses a single-day cycle to one date', () => {
    expect(cycleLabel(RecurrenceUnit.DAY, 1, utc(2026, 7, 1), utc(2026, 7, 2))).toBe('01 Jul');
  });

  it('falls back to a day range when there is no cadence', () => {
    expect(cycleLabel(null, 1, utc(2026, 7, 1), utc(2026, 7, 5))).toBe('01 Jul – 04 Jul');
  });
});
