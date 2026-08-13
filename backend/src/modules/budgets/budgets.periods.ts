import { RecurrenceUnit } from '../../core/prisma.js';

const DAY = 86_400_000;
const HOUR = 3_600_000;

/** Calendar-month bounds for a YYYY-MM (or the current month). Used across analytics/dashboard. */
export function monthRange(month?: string): { start: Date; end: Date } {
  const now = new Date();
  let y = now.getUTCFullYear();
  let m = now.getUTCMonth() + 1;
  if (month) {
    const parts = month.split('-');
    y = Number(parts[0]);
    m = Number(parts[1]);
  }
  return {
    start: new Date(Date.UTC(y, m - 1, 1)),
    end: new Date(Date.UTC(y, m, 1)),
  };
}

/** Reference date for "current period": the 1st of a YYYY-MM, or today. */
export function refDate(month?: string): Date {
  if (month) {
    const [y, m] = month.split('-').map(Number);
    return new Date(Date.UTC(y!, (m ?? 1) - 1, 1));
  }
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

/** Add N months keeping the day-of-month, clamping 29-31 to the month's last day. */
function clampedMonthShift(d: Date, months: number): Date {
  const target = d.getUTCDate();
  const next = new Date(
    Date.UTC(
      d.getUTCFullYear(),
      d.getUTCMonth() + months,
      1,
      d.getUTCHours(),
      d.getUTCMinutes(),
      d.getUTCSeconds(),
    ),
  );
  const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
  next.setUTCDate(Math.min(target, lastDay));
  return next;
}

/**
 * One cadence step later: "every `interval` `unit`". Month-based units keep the
 * day-of-month and clamp into shorter months, so "the 31st" still works in
 * February.
 */
export function addRecurrence(unit: RecurrenceUnit, interval: number, from: Date): Date {
  const n = Math.max(1, Math.trunc(interval));
  switch (unit) {
    case RecurrenceUnit.HOUR:
      return new Date(from.getTime() + n * HOUR);
    case RecurrenceUnit.DAY:
      return new Date(from.getTime() + n * DAY);
    case RecurrenceUnit.WEEK:
      return new Date(from.getTime() + n * 7 * DAY);
    case RecurrenceUnit.MONTH:
      return clampedMonthShift(from, n);
    case RecurrenceUnit.QUARTER:
      return clampedMonthShift(from, 3 * n);
    case RecurrenceUnit.YEAR:
      return clampedMonthShift(from, 12 * n);
  }
}

/**
 * Which cycle a date belongs to.
 *
 * Not "which cycle is open right now" - that is what the code used to stamp, and
 * it meant a receipt typed up on the 2nd for a purchase made on the 30th landed
 * in the wrong month, permanently, in a snapshot that is never recomputed. A
 * phone syncing three days late did the same thing to every queued expense.
 *
 * `pastCycles` are the closed cycles, newest or oldest order does not matter.
 * Dates beyond the current cycle project forward, so a future-dated expense
 * waits in the cycle it actually belongs to instead of inflating this one.
 */
export function cycleIndexForDate(
  budget: {
    kind: 'ONE_TIME' | 'RECURRING' | 'UNPLANNED';
    cycleIndex: number;
    cycleStartedAt: Date;
    nextResetAt: Date | null;
    recurrenceUnit: RecurrenceUnit | null;
    recurrenceInterval: number;
  },
  date: Date,
  pastCycles: Array<{ index: number; startedAt: Date; endedAt: Date }> = [],
): number {
  // A one-time plan has exactly one cycle, whatever the date says.
  if (budget.kind !== 'RECURRING' || !budget.recurrenceUnit) return 0;

  if (date >= budget.cycleStartedAt) {
    // Inside the open cycle, or past its end for a plan that has not rolled yet.
    if (!budget.nextResetAt || date < budget.nextResetAt) return budget.cycleIndex;

    let index = budget.cycleIndex;
    let edge = budget.nextResetAt;
    // Generous but finite: an hourly plan dated a year out would otherwise spin.
    for (let steps = 0; steps < 10_000 && date >= edge; steps += 1) {
      index += 1;
      edge = addRecurrence(budget.recurrenceUnit, budget.recurrenceInterval, edge);
    }
    return index;
  }

  const closed = pastCycles.find((c) => date >= c.startedAt && date < c.endedAt);
  if (closed) return closed.index;

  // Older than anything on record - a plan that skipped snapshotting quiet
  // cycles, or a date from before the plan existed. Walk back from the open one.
  let index = budget.cycleIndex;
  let edge = budget.cycleStartedAt;
  for (let steps = 0; steps < 10_000 && date < edge && index > 0; steps += 1) {
    index -= 1;
    edge = subRecurrence(budget.recurrenceUnit, budget.recurrenceInterval, edge);
  }
  return Math.max(0, index);
}

/** One cadence step earlier. The mirror of `addRecurrence`, for walking back. */
export function subRecurrence(unit: RecurrenceUnit, interval: number, from: Date): Date {
  const n = Math.max(1, Math.trunc(interval));
  switch (unit) {
    case RecurrenceUnit.HOUR:
      return new Date(from.getTime() - n * HOUR);
    case RecurrenceUnit.DAY:
      return new Date(from.getTime() - n * DAY);
    case RecurrenceUnit.WEEK:
      return new Date(from.getTime() - n * 7 * DAY);
    case RecurrenceUnit.MONTH:
      return clampedMonthShift(from, -n);
    case RecurrenceUnit.QUARTER:
      return clampedMonthShift(from, -3 * n);
    case RecurrenceUnit.YEAR:
      return clampedMonthShift(from, -12 * n);
  }
}

const UNIT_NOUN: Record<RecurrenceUnit, string> = {
  [RecurrenceUnit.HOUR]: 'hour',
  [RecurrenceUnit.DAY]: 'day',
  [RecurrenceUnit.WEEK]: 'week',
  [RecurrenceUnit.MONTH]: 'month',
  [RecurrenceUnit.QUARTER]: 'quarter',
  [RecurrenceUnit.YEAR]: 'year',
};

/** The noun a cycle is measured in - "month", "6 hours", "3 days". */
export function periodNoun(unit: RecurrenceUnit, interval: number): string {
  const n = Math.max(1, Math.trunc(interval));
  return n === 1 ? UNIT_NOUN[unit] : `${n} ${UNIT_NOUN[unit]}s`;
}

/** Everyday name for a cadence: "monthly", "every 6 hours", "every 2 weeks". */
export function recurrenceLabel(unit: RecurrenceUnit, interval: number): string {
  const n = Math.max(1, Math.trunc(interval));
  if (n === 1) {
    switch (unit) {
      case RecurrenceUnit.HOUR:
        return 'hourly';
      case RecurrenceUnit.DAY:
        return 'daily';
      case RecurrenceUnit.WEEK:
        return 'weekly';
      case RecurrenceUnit.MONTH:
        return 'monthly';
      case RecurrenceUnit.QUARTER:
        return 'quarterly';
      case RecurrenceUnit.YEAR:
        return 'yearly';
    }
  }
  return `every ${n} ${UNIT_NOUN[unit]}s`;
}

const fmtDay = (x: Date) =>
  new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', timeZone: 'UTC' }).format(x);
const fmtDayTime = (x: Date) =>
  new Intl.DateTimeFormat('en-GB', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'UTC',
  }).format(x);

/**
 * Human label for one cycle window. Sub-day cadences need the clock time to be
 * distinguishable; a whole calendar month is just named.
 */
export function cycleLabel(
  unit: RecurrenceUnit | null,
  interval: number,
  start: Date,
  end: Date,
): string {
  const n = Math.max(1, Math.trunc(interval));

  if (unit === RecurrenceUnit.HOUR) {
    return `${fmtDayTime(start)} – ${fmtDayTime(end)}`;
  }
  if (unit === RecurrenceUnit.MONTH && n === 1 && start.getUTCDate() === 1) {
    return new Intl.DateTimeFormat('en-GB', {
      month: 'long',
      year: 'numeric',
      timeZone: 'UTC',
    }).format(start);
  }
  if (unit === RecurrenceUnit.YEAR && n === 1 && start.getUTCMonth() === 0 && start.getUTCDate() === 1) {
    return String(start.getUTCFullYear());
  }

  const last = new Date(end.getTime() - DAY);
  const sameYear = start.getUTCFullYear() === last.getUTCFullYear();
  const suffix = sameYear ? '' : ` ${last.getUTCFullYear()}`;
  return start.getTime() >= last.getTime()
    ? fmtDay(start)
    : `${fmtDay(start)} – ${fmtDay(last)}${suffix}`;
}
