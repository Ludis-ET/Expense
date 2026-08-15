import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { accountIdParam, createAccountSchema, updateAccountSchema } from './accounts.schema.js';
import * as accounts from './accounts.service.js';

export const accountsRouter = Router();

accountsRouter.use(requireAuth);

accountsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await accounts.list(req.user!));
  }),
);

/**
 * What this one wallet is holding, and for which plans.
 *
 * The other half of the reservation story: the plan page has always been able to
 * say where its money sits, but a wallet showing "12,000 set aside" had no way
 * to name who set it aside. Drives the wallet sheet.
 */
accountsRouter.get(
  '/:id/reservations',
  validate({ params: accountIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await accounts.reservations(req.user!, req.params.id!));
  }),
);

accountsRouter.post(
  '/',
  validate({ body: createAccountSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await accounts.create(req.user!, req.body));
  }),
);

accountsRouter.put(
  '/:id',
  validate({ params: accountIdParam, body: updateAccountSchema }),
  asyncHandler(async (req, res) => {
    res.json(await accounts.update(req.user!, req.params.id!, req.body));
  }),
);

accountsRouter.delete(
  '/:id',
  validate({ params: accountIdParam }),
  asyncHandler(async (req, res) => {
    await accounts.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
