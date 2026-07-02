import type { RequestHandler } from 'express';
import { logger } from '../../core/logger.js';
import { catchUpUser } from './recurring.engine.js';

/** Per-user debounce so bursts of requests don't hammer the DB. */
const DEBOUNCE_MS = 5 * 60 * 1000;
const lastRun = new Map<string, number>();

/**
 * Fire-and-forget lazy execution of due recurring rules. Mounted after
 * requireAuth on routes that display transaction-derived data, so occurrences
 * are materialized before (or at worst, just after) the user looks at them.
 */
export const recurringCatchUp: RequestHandler = (req, _res, next) => {
  const userId = req.user?.id;
  if (userId) {
    const prev = lastRun.get(userId) ?? 0;
    const now = Date.now();
    if (now - prev > DEBOUNCE_MS) {
      lastRun.set(userId, now);
      catchUpUser(userId).catch((err) => {
        lastRun.delete(userId); // allow a retry on the next request
        logger.error({ err, userId }, 'recurring catch-up failed');
      });
    }
  }
  next();
};
