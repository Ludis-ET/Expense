import type { RequestHandler } from 'express';
import { logger } from '../../core/logger.js';
import { syncReminders } from './ledger.reminders.js';

const DEBOUNCE_MS = 5 * 60 * 1000;
const lastRun = new Map<string, number>();

/** Lazy tab due-date reminders - same debounce pattern as recurring catch-up. */
export const tabReminderCatchUp: RequestHandler = (req, _res, next) => {
  const userId = req.user?.id;
  if (userId) {
    const prev = lastRun.get(userId) ?? 0;
    const now = Date.now();
    if (now - prev > DEBOUNCE_MS) {
      lastRun.set(userId, now);
      syncReminders(userId).catch((err) => {
        lastRun.delete(userId);
        logger.error({ err, userId }, 'tab reminder sync failed');
      });
    }
  }
  next();
};
