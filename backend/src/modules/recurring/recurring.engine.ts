import { Frequency, type RecurringRule } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { logger } from '../../core/logger.js';
import { notify } from '../notifications/notifications.service.js';

/** Runaway guard: a rule can post at most this many missed occurrences per catch-up. */
const MAX_OCCURRENCES = 120;

/**
 * The next scheduled occurrence after `from`, honouring interval and, for
 * MONTHLY rules, clamping dayOfMonth 29–31 to the last day of shorter months.
 */
export function advanceNextRun(
  rule: Pick<RecurringRule, 'frequency' | 'interval' | 'dayOfMonth'>,
  from: Date,
): Date {
  const d = new Date(from);
  switch (rule.frequency) {
    case Frequency.DAILY:
      d.setUTCDate(d.getUTCDate() + rule.interval);
      return d;
    case Frequency.WEEKLY:
      d.setUTCDate(d.getUTCDate() + 7 * rule.interval);
      return d;
    case Frequency.MONTHLY: {
      const target = rule.dayOfMonth ?? from.getUTCDate();
      // Move to the 1st first so adding months can't skip (e.g. Jan 31 + 1mo).
      const next = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + rule.interval, 1, d.getUTCHours(), d.getUTCMinutes()));
      const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
      next.setUTCDate(Math.min(target, lastDay));
      return next;
    }
    case Frequency.YEARLY:
      return new Date(Date.UTC(d.getUTCFullYear() + rule.interval, d.getUTCMonth(), d.getUTCDate(), d.getUTCHours(), d.getUTCMinutes()));
  }
}

/**
 * Materialize all due occurrences for a user's active rules. autoPost rules
 * create transactions dated at each scheduled time; remind-only rules fire a
 * notification. Runs in one DB transaction so a crash can't double-post.
 */
export async function catchUpUser(userId: string): Promise<void> {
  const now = new Date();

  await prisma.$transaction(async (dbTx) => {
    const due = await dbTx.recurringRule.findMany({
      where: { userId, active: true, nextRun: { lte: now } },
    });

    for (const rule of due) {
      let nextRun = rule.nextRun;
      let posted = 0;

      while (nextRun <= now && posted < MAX_OCCURRENCES) {
        if (rule.endDate && nextRun > rule.endDate) break;

        if (rule.autoPost) {
          await dbTx.transaction.create({
            data: {
              userId,
              kind: rule.kind,
              amount: rule.amount,
              currency: rule.currency,
              date: nextRun,
              accountId: rule.accountId,
              categoryId: rule.categoryId,
              payee: rule.payee,
              note: rule.note,
              recurringRuleId: rule.id,
            },
          });
        } else {
          await notify(
            userId,
            'recurring_due',
            `Reminder: ${rule.name} (${rule.amount.toFixed(2)} ${rule.currency}) is due.`,
            '/recurring',
          );
        }

        nextRun = advanceNextRun(rule, nextRun);
        posted += 1;
      }

      const expired = rule.endDate ? nextRun > rule.endDate : false;
      await dbTx.recurringRule.update({
        where: { id: rule.id },
        data: { nextRun, lastRunAt: now, ...(expired ? { active: false } : {}) },
      });
    }
  });

  logger.debug({ userId }, 'recurring catch-up complete');
}
