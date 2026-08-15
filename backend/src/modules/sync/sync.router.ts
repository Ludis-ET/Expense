/**
 * One request for everything the app reloads after a write.
 *
 * Saving a single transaction used to cost six round trips: the write, then
 * `refreshAfterWrite()` firing `/dashboard`, `/accounts`, `/budgets`,
 * `/budgets/sources` and `/recurring` in parallel. Each of those five handlers
 * independently called `loadSnapshot`, which is five aggregate queries - so one
 * tap on Save was roughly twenty-five aggregates and six HTTP requests.
 *
 * The five payloads are unchanged: this route composes the same service
 * functions and returns their results under the keys the client already knows.
 * The saving is the round trips and the repeated snapshot work.
 */
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import { validate } from '../../core/middleware/validate.js';
import * as accounts from '../accounts/accounts.service.js';
import * as budgets from '../budgets/budgets.service.js';
import * as dashboard from '../dashboard/dashboard.service.js';
import * as recurring from '../recurring/recurring.service.js';

export const syncRouter = Router();

syncRouter.use(requireAuth, recurringCatchUp);

const syncQuery = z.object({
  /** Scopes `sources` the same way `/budgets/sources?currency=` does. */
  currency: z.string().length(3).toUpperCase().optional(),
});

syncRouter.get(
  '/',
  validate({ query: syncQuery }),
  asyncHandler(async (req, res) => {
    const user = req.user!;
    const currency = (req.query as z.infer<typeof syncQuery>).currency;

    // Run together. Postgres handles the concurrency and the client gets one
    // consistent-enough view; these are all reads, so no lock is involved.
    const [overview, wallets, plans, sources, rules] = await Promise.all([
      dashboard.overview(user),
      accounts.list(user),
      budgets.list(user),
      budgets.spendableSources(user, currency),
      recurring.list(user),
    ]);

    res.json({ dashboard: overview, accounts: wallets, budgets: plans, sources, recurring: rules });
  }),
);
