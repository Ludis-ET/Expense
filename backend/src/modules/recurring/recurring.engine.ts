import { Frequency, TxKind, type RecurringRule } from "../../core/prisma.js";
import { prisma } from "../../core/db.js";
import { logger } from "../../core/logger.js";
import { notify } from "../notifications/notifications.service.js";
import { postTransaction } from "../../core/money/postings.js";

/** Runaway guard: a rule can post at most this many missed occurrences per catch-up. */
const MAX_OCCURRENCES = 120;

/**
 * The next scheduled occurrence after `from`, honouring interval and, for
 * MONTHLY rules, clamping dayOfMonth 29–31 to the last day of shorter months.
 */
export function advanceNextRun(
  rule: Pick<RecurringRule, "frequency" | "interval" | "dayOfMonth">,
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
      const next = new Date(
        Date.UTC(
          d.getUTCFullYear(),
          d.getUTCMonth() + rule.interval,
          1,
          d.getUTCHours(),
          d.getUTCMinutes(),
        ),
      );
      const lastDay = new Date(
        Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0),
      ).getUTCDate();
      next.setUTCDate(Math.min(target, lastDay));
      return next;
    }
    case Frequency.YEARLY:
      return new Date(
        Date.UTC(
          d.getUTCFullYear() + rule.interval,
          d.getUTCMonth(),
          d.getUTCDate(),
          d.getUTCHours(),
          d.getUTCMinutes(),
        ),
      );
  }
}

export type OccurrenceKind = "transaction" | "held" | "reminder";

/**
 * Materialize one occurrence of a rule.
 *
 * A scheduled rule is a *prediction*, not an observation: nobody watched this
 * money move. Forcing it through was how rent could quietly overdraw a wallet or
 * eat what a plan had reserved - the write skipped every guard. Now it goes
 * through the posting core, and when the money genuinely is not there the
 * occurrence is held and the user is told, which is the honest outcome.
 */
export async function applyOccurrence(
  userId: string,
  rule: RecurringRule,
  date: Date,
): Promise<OccurrenceKind> {
  try {
    await postTransaction(userId, {
      kind: rule.kind,
      amount: rule.amount,
      currency: rule.currency,
      date,
      accountId: rule.accountId,
      categoryId: rule.categoryId,
      // A subscription can draw down its own envelope instead of showing up as
      // unplanned spending every single month.
      budgetId: rule.kind === TxKind.EXPENSE ? rule.budgetId : null,
      payee: rule.payee,
      note: rule.note,
      recurringRuleId: rule.id,
      // The rule and the occurrence date identify this posting exactly, so a
      // catch-up that runs twice cannot post it twice.
      clientOpId: `rule:${rule.id}:${date.toISOString()}`,
    });
    return "transaction";
  } catch (err) {
    const reason = err instanceof Error ? err.message : "the money was not available";
    await notify(
      userId,
      "recurring_held",
      `${rule.name} (${rule.amount.toFixed(2)} ${rule.currency}) was due but has not been recorded: ${reason}`,
      "/recurring",
    );
    return "held";
  }
}

/**
 * Materialize all due occurrences for a user's active rules.
 *
 * Each occurrence is its own transaction now rather than all of them sharing
 * one: the posting core takes a per-user lock, and holding an outer transaction
 * across every rule would deadlock against it. Idempotency does the job the
 * single transaction used to - a crash halfway through cannot double-post,
 * because a replay recognises what already landed.
 */
export async function catchUpUser(userId: string): Promise<void> {
  const now = new Date();
  const due = await prisma.recurringRule.findMany({
    where: { userId, active: true, nextRun: { lte: now } },
  });

  for (const rule of due) {
    let nextRun = rule.nextRun;
    let posted = 0;
    let held = 0;

    while (nextRun <= now && posted < MAX_OCCURRENCES) {
      if (rule.endDate && nextRun > rule.endDate) break;

      if (rule.autoPost) {
        const outcome = await applyOccurrence(userId, rule, nextRun);
        if (outcome === "held") held += 1;
      } else {
        await notify(
          userId,
          "recurring_due",
          `Reminder: ${rule.name} (${rule.amount.toFixed(2)} ${rule.currency}) is due.`,
          "/recurring",
        );
      }

      nextRun = advanceNextRun(rule, nextRun);
      posted += 1;
    }

    const expired = rule.endDate ? nextRun > rule.endDate : false;
    await prisma.recurringRule.update({
      where: { id: rule.id },
      data: {
        nextRun,
        lastRunAt: now,
        ...(expired ? { active: false } : {}),
      },
    });

    if (held > 0) {
      logger.debug({ userId, rule: rule.id, held }, "recurring occurrences held");
    }
  }

  logger.debug({ userId }, "recurring catch-up complete");
}
