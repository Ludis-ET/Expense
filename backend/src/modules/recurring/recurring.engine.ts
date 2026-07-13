import { Frequency, Prisma, WishlistStatus, type RecurringRule } from '../../core/prisma.js';
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

export type OccurrenceKind = 'transaction' | 'goal' | 'wishlist';

/**
 * Materialize one occurrence of a rule inside an open DB transaction:
 * - savings plan targeting a goal → adds a goal contribution (and marks the
 *   goal achieved on completion). A linked GOAL spend-lock grows automatically.
 * - savings plan targeting a wishlist item → funds the want (and mirrors into
 *   its linked goal, matching the manual Fund flow).
 * - otherwise → posts a normal transaction.
 */
export async function applyOccurrence(
  dbTx: Prisma.TransactionClient,
  userId: string,
  rule: RecurringRule,
  date: Date,
): Promise<OccurrenceKind> {
  if (rule.goalId) {
    const goal = await dbTx.savingsGoal.findUnique({ where: { id: rule.goalId } });
    await dbTx.goalContribution.create({
      data: { goalId: rule.goalId, amount: rule.amount, date, note: `Auto-save: ${rule.name}` },
    });
    if (goal && !goal.achievedAt) {
      const agg = await dbTx.goalContribution.aggregate({ where: { goalId: rule.goalId }, _sum: { amount: true } });
      if ((agg._sum.amount ?? new Prisma.Decimal(0)).gte(goal.targetAmount)) {
        await dbTx.savingsGoal.update({ where: { id: goal.id }, data: { achievedAt: new Date() } });
        await notify(userId, 'goal_achieved', `🎉 Auto-save reached your "${goal.name}" goal!`, '/budgets?tab=goals');
      }
    }
    return 'goal';
  }

  if (rule.wishlistItemId) {
    const item = await dbTx.wishlistItem.findUnique({ where: { id: rule.wishlistItemId } });
    if (item && item.status !== WishlistStatus.BOUGHT && item.status !== WishlistStatus.DROPPED) {
      const cost = item.estimatedCost;
      const wasFunded = item.savedAmount.gte(cost);
      const nextSaved = Prisma.Decimal.min(cost, item.savedAmount.add(rule.amount));
      await dbTx.wishlistItem.update({
        where: { id: item.id },
        data: {
          savedAmount: nextSaved,
          status: item.status === WishlistStatus.WANTING ? WishlistStatus.SAVING : item.status,
        },
      });
      if (item.goalId) {
        await dbTx.goalContribution.create({
          data: { goalId: item.goalId, amount: rule.amount, date, note: `Auto-save: ${rule.name}` },
        });
      }
      if (!wasFunded && nextSaved.gte(cost)) {
        await notify(userId, 'wishlist_funded', `🎯 Auto-save fully funded "${item.name}" — ready to buy!`, '/wishlist');
      }
    }
    return 'wishlist';
  }

  await dbTx.transaction.create({
    data: {
      userId,
      kind: rule.kind,
      amount: rule.amount,
      currency: rule.currency,
      date,
      accountId: rule.accountId,
      categoryId: rule.categoryId,
      payee: rule.payee,
      note: rule.note,
      recurringRuleId: rule.id,
    },
  });
  return 'transaction';
}

function reminderLink(rule: RecurringRule): string {
  if (rule.goalId) return '/budgets?tab=goals';
  if (rule.wishlistItemId) return '/wishlist';
  return '/recurring';
}

/**
 * Materialize all due occurrences for a user's active rules. autoPost rules
 * create transactions / savings contributions dated at each scheduled time;
 * remind-only rules fire a notification. Runs in one DB transaction so a crash
 * can't double-post.
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
          await applyOccurrence(dbTx, userId, rule, nextRun);
        } else {
          await notify(
            userId,
            'recurring_due',
            `Reminder: ${rule.name} (${rule.amount.toFixed(2)} ${rule.currency}) is due.`,
            reminderLink(rule),
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
