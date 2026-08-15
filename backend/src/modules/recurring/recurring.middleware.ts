import type { RequestHandler } from 'express';
import { runClaimed } from '../../core/catch-up-claim.js';
import { catchUpUser } from './recurring.engine.js';

/**
 * Fire-and-forget lazy execution of due recurring rules. Mounted after
 * requireAuth on routes that display transaction-derived data, so occurrences
 * are materialized before (or at worst, just after) the user looks at them.
 *
 * The debounce lives in the database - see `claimCatchUp` - so it survives a
 * restart and holds across replicas.
 */
export const recurringCatchUp: RequestHandler = (req, _res, next) => {
  const userId = req.user?.id;
  if (userId) runClaimed(userId, 'lastCatchUpAt', 'recurring catch-up', catchUpUser);
  next();
};
