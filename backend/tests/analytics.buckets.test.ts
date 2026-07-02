import { describe, expect, it } from 'vitest';
import {
  bucketKey,
  dayKey,
  enumerateBuckets,
  monthKey,
  weekStart,
} from '../src/modules/analytics/analytics.buckets.js';

const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d));

describe('keys', () => {
  it('dayKey formats YYYY-MM-DD', () => {
    expect(dayKey(utc(2026, 7, 2))).toBe('2026-07-02');
  });

  it('monthKey formats YYYY-MM', () => {
    expect(monthKey(utc(2026, 7, 2))).toBe('2026-07');
  });
});

describe('weekStart', () => {
  it('finds Monday for a mid-week date (Monday start)', () => {
    // 2026-07-02 is a Thursday → Monday is 2026-06-29
    expect(dayKey(weekStart(utc(2026, 7, 2), 1))).toBe('2026-06-29');
  });

  it('finds Sunday for a mid-week date (Sunday start)', () => {
    expect(dayKey(weekStart(utc(2026, 7, 2), 0))).toBe('2026-06-28');
  });

  it('returns the same day when the date is the week start', () => {
    // 2026-06-29 is a Monday
    expect(dayKey(weekStart(utc(2026, 6, 29), 1))).toBe('2026-06-29');
  });
});

describe('bucketKey', () => {
  it('routes to the right granularity', () => {
    const d = utc(2026, 7, 2);
    expect(bucketKey(d, 'day', 1)).toBe('2026-07-02');
    expect(bucketKey(d, 'week', 1)).toBe('2026-06-29');
    expect(bucketKey(d, 'month', 1)).toBe('2026-07');
  });
});

describe('enumerateBuckets', () => {
  it('enumerates days inclusively', () => {
    const keys = enumerateBuckets(utc(2026, 6, 28), utc(2026, 7, 2), 'day', 1);
    expect(keys).toEqual(['2026-06-28', '2026-06-29', '2026-06-30', '2026-07-01', '2026-07-02']);
  });

  it('enumerates weeks aligned to the week start', () => {
    const keys = enumerateBuckets(utc(2026, 6, 24), utc(2026, 7, 8), 'week', 1);
    expect(keys).toEqual(['2026-06-22', '2026-06-29', '2026-07-06']);
  });

  it('enumerates months', () => {
    const keys = enumerateBuckets(utc(2026, 5, 15), utc(2026, 7, 2), 'month', 1);
    expect(keys).toEqual(['2026-05', '2026-06', '2026-07']);
  });
});
