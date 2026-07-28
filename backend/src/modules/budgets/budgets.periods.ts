import { BudgetPeriod } from '../../core/prisma.js';

const DAY = 86_400_000;

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

/** The same clock time one period later. Recurring plans reset on this cadence. */
export function addPeriod(period: BudgetPeriod, from: Date): Date {
  const d = new Date(from);
  switch (period) {
    case BudgetPeriod.WEEKLY:
      d.setUTCDate(d.getUTCDate() + 7);
      return d;
    case BudgetPeriod.MONTHLY:
      return clampedMonthShift(d, 1);
    case BudgetPeriod.QUARTERLY:
      return clampedMonthShift(d, 3);
    case BudgetPeriod.YEARLY:
      return clampedMonthShift(d, 12);
  }
}

/** Add N months keeping the day-of-month, clamping 29-31 to the month's last day. */
function clampedMonthShift(d: Date, months: number): Date {
  const target = d.getUTCDate();
  const next = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, 1, d.getUTCHours(), d.getUTCMinutes()),
  );
  const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
  next.setUTCDate(Math.min(target, lastDay));
  return next;
}

const fmtDay = (x: Date) =>
  new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', timeZone: 'UTC' }).format(x);

/** Human label for one cycle window, e.g. "March 2026" or "01 Mar – 07 Mar". */
export function cycleLabel(period: BudgetPeriod | null, start: Date, end: Date): string {
  switch (period) {
    case BudgetPeriod.MONTHLY:
      return new Intl.DateTimeFormat('en-GB', {
        month: 'long',
        year: 'numeric',
        timeZone: 'UTC',
      }).format(start);
    case BudgetPeriod.QUARTERLY:
      return `${fmtDay(start)} – ${fmtDay(new Date(end.getTime() - DAY))} ${end.getUTCFullYear()}`;
    case BudgetPeriod.YEARLY:
      return `${start.getUTCFullYear()}–${end.getUTCFullYear()}`;
    default:
      return `${fmtDay(start)} – ${fmtDay(new Date(end.getTime() - DAY))}`;
  }
}

export const PERIOD_NOUN: Record<BudgetPeriod, string> = {
  [BudgetPeriod.WEEKLY]: 'week',
  [BudgetPeriod.MONTHLY]: 'month',
  [BudgetPeriod.QUARTERLY]: 'quarter',
  [BudgetPeriod.YEARLY]: 'year',
};
