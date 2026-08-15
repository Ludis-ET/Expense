import { LedgerStatus, Prisma } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { notify } from '../notifications/notifications.service.js';

const zero = new Prisma.Decimal(0);

function entryLink(entryId: string) {
  return `/tab?e=${entryId}`;
}

function startOfUtcDay(d: Date) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function startOfUtcWeek(d: Date) {
  const day = startOfUtcDay(d);
  const dow = day.getUTCDay();
  day.setUTCDate(day.getUTCDate() - dow);
  return day;
}

/** Push due-soon and overdue notifications for open tab entries (deduped). */
export async function syncReminders(userId: string): Promise<void> {
  const now = new Date();
  const inThreeDays = new Date(now.getTime() + 3 * 86_400_000);
  const todayStart = startOfUtcDay(now);
  const weekStart = startOfUtcWeek(now);

  const entries = await prisma.ledgerEntry.findMany({
    where: { userId, status: LedgerStatus.OPEN, dueDate: { not: null } },
    include: { payments: { select: { amount: true } } },
  });

  for (const entry of entries) {
    const paid = entry.payments.reduce((s, p) => s.add(p.amount), zero);
    const remaining = entry.totalAmount.sub(paid);
    if (!remaining.gt(0) || !entry.dueDate) continue;

    const link = entryLink(entry.id);
    const label = entry.title?.trim() || entry.counterparty;
    const amt = remaining.toFixed(2);

    // The period lives in the dedupe key - one overdue notice per entry per
    // week, one due notice per entry per day - so the upsert enforces the
    // cadence that a per-entry `findFirst` used to check with an extra query
    // each, and does it atomically rather than racily.
    if (entry.dueDate < now) {
      await notify(
        userId,
        'tab_overdue',
        `⚠️ Overdue tab: ${label} - ${amt} ${entry.currency} was due ${entry.dueDate.toISOString().slice(0, 10)}`,
        link,
        `tab_overdue:${entry.id}:${weekStart.toISOString().slice(0, 10)}`,
        // Same week, same news. Re-marking it unread on every five-minute
        // sweep would be nagging.
        { resurface: false },
      );
      continue;
    }

    if (entry.dueDate <= inThreeDays) {
      const days = Math.max(0, Math.ceil((entry.dueDate.getTime() - now.getTime()) / 86_400_000));
      await notify(
        userId,
        'tab_due',
        `📅 Due ${days === 0 ? 'today' : `in ${days} day${days === 1 ? '' : 's'}`}: ${label} - ${amt} ${entry.currency}`,
        link,
        `tab_due:${entry.id}:${todayStart.toISOString().slice(0, 10)}`,
        { resurface: false },
      );
    }
  }
}
