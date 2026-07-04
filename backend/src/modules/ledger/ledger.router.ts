import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { tabReminderCatchUp } from './ledger.middleware.js';
import {
  createLedgerSchema,
  ledgerIdParam,
  listLedgerQuery,
  recordPaymentSchema,
  updateLedgerSchema,
} from './ledger.schema.js';
import * as ledger from './ledger.service.js';

export const ledgerRouter = Router();

ledgerRouter.use(requireAuth, tabReminderCatchUp);

ledgerRouter.get(
  '/summary',
  asyncHandler(async (req, res) => {
    res.json(await ledger.summary(req.user!));
  }),
);

ledgerRouter.get(
  '/people',
  asyncHandler(async (req, res) => {
    res.json(await ledger.people(req.user!));
  }),
);

ledgerRouter.get(
  '/',
  validate({ query: listLedgerQuery }),
  asyncHandler(async (req, res) => {
    res.json(await ledger.list(req.user!, req.query as never));
  }),
);

ledgerRouter.post(
  '/',
  validate({ body: createLedgerSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await ledger.create(req.user!, req.body));
  }),
);

ledgerRouter.put(
  '/:id',
  validate({ params: ledgerIdParam, body: updateLedgerSchema }),
  asyncHandler(async (req, res) => {
    res.json(await ledger.update(req.user!, req.params.id!, req.body));
  }),
);

ledgerRouter.post(
  '/:id/payments',
  validate({ params: ledgerIdParam, body: recordPaymentSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await ledger.recordPayment(req.user!, req.params.id!, req.body));
  }),
);

ledgerRouter.post(
  '/:id/cancel',
  validate({ params: ledgerIdParam }),
  asyncHandler(async (req, res) => {
    await ledger.cancel(req.user!, req.params.id!);
    res.status(204).end();
  }),
);

ledgerRouter.delete(
  '/:id',
  validate({ params: ledgerIdParam }),
  asyncHandler(async (req, res) => {
    await ledger.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
