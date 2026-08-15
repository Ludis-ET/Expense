import type { RequestHandler } from 'express';
import { runClaimed } from '../../core/catch-up-claim.js';
import { syncReminders } from './ledger.reminders.js';

/**
 * Lazy tab due-date reminders. Shares the database-backed claim with the
 * recurring catch-up, so the two cannot both fire for the same user in the
 * same window and cannot duplicate across replicas.
 */
export const tabReminderCatchUp: RequestHandler = (req, _res, next) => {
  const userId = req.user?.id;
  if (userId) runClaimed(userId, 'lastReminderSyncAt', 'tab reminder sync', syncReminders);
  next();
};
