/**
 * Pure date-bucketing helpers for the analytics series endpoints.
 * Kept dependency-free so they can be unit-tested directly.
 */

export type Granularity = 'day' | 'week' | 'month';

/** YYYY-MM-DD in UTC. */
export function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** YYYY-MM in UTC. */
export function monthKey(d: Date): string {
  return d.toISOString().slice(0, 7);
}

/**
 * The date (UTC midnight) of the start of the week containing `d`.
 * `firstDayOfWeek`: 0 = Sunday, 1 = Monday.
 */
export function weekStart(d: Date, firstDayOfWeek: number): Date {
  const day = d.getUTCDay(); // 0..6, Sunday = 0
  const diff = (day - firstDayOfWeek + 7) % 7;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - diff));
}

/** Bucket key for a date at the given granularity. */
export function bucketKey(d: Date, granularity: Granularity, firstDayOfWeek: number): string {
  switch (granularity) {
    case 'day':
      return dayKey(d);
    case 'week':
      return dayKey(weekStart(d, firstDayOfWeek));
    case 'month':
      return monthKey(d);
  }
}

/** All bucket keys between from and to inclusive, so charts have no gaps. */
export function enumerateBuckets(
  from: Date,
  to: Date,
  granularity: Granularity,
  firstDayOfWeek: number,
): string[] {
  const keys: string[] = [];
  const cursor =
    granularity === 'week'
      ? weekStart(from, firstDayOfWeek)
      : granularity === 'month'
        ? new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), 1))
        : new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), from.getUTCDate()));

  while (cursor <= to) {
    keys.push(granularity === 'month' ? monthKey(cursor) : dayKey(cursor));
    if (granularity === 'day') cursor.setUTCDate(cursor.getUTCDate() + 1);
    else if (granularity === 'week') cursor.setUTCDate(cursor.getUTCDate() + 7);
    else cursor.setUTCMonth(cursor.getUTCMonth() + 1);
  }
  return keys;
}
