import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import * as money from './money.service.js';

export const moneyRouter = Router();

moneyRouter.use(requireAuth);

const movementsQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(25),
});

const movementIdParam = z.object({ id: z.string().min(1) });

const settleDriftSchema = z.object({
  accountId: z.string().min(1),
  /** Where the missing movement is filed. */
  categoryId: z.string().min(1),
});

/** Everything that moved money recently, newest first, across all three ledgers. */
moneyRouter.get(
  '/movements',
  validate({ query: movementsQuery }),
  asyncHandler(async (req, res) => {
    res.json(await money.movements(req.user!, Number(req.query.limit ?? 25)));
  }),
);

/**
 * Take a movement back. It is removed, not reversed - a mistake should leave no
 * trace. Refused when doing so would leave the books unbalanced.
 */
moneyRouter.post(
  '/movements/:id/undo',
  validate({ params: movementIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await money.undo(req.user!, req.params.id!));
  }),
);

/** Does this user's money add up? Plus everything needed to act on the answer. */
moneyRouter.get(
  '/health',
  asyncHandler(async (req, res) => {
    const currency = typeof req.query.currency === 'string' ? req.query.currency : undefined;
    res.json(await money.health(req.user!, currency));
  }),
);

/** Put the books right, and report exactly what moved. */
moneyRouter.post(
  '/health/fix',
  asyncHandler(async (req, res) => {
    res.json(await money.fix(req.user!));
  }),
);

/** Free money per currency: what you have that is not in any plan. */
moneyRouter.get(
  '/ready-to-assign',
  asyncHandler(async (req, res) => {
    res.json(await money.assignable(req.user!));
  }),
);

/** Wallets where the bank's own reported balance disagrees with ours. */
moneyRouter.get(
  '/drift',
  asyncHandler(async (req, res) => {
    const { driftReport } = await import('../accounts/accounts.service.js');
    res.json(await driftReport(req.user!));
  }),
);

/** Record the difference as a real movement so the wallet matches the bank. */
moneyRouter.post(
  '/drift/settle',
  validate({ body: settleDriftSchema }),
  asyncHandler(async (req, res) => {
    const { settleDrift } = await import('../accounts/accounts.service.js');
    res.json(await settleDrift(req.user!, req.body.accountId, req.body.categoryId));
  }),
);
