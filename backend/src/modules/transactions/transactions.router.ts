import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import {
  createTransactionSchema,
  listTransactionsQuery,
  transactionIdParam,
  updateTransactionSchema,
} from './transactions.schema.js';
import * as transactions from './transactions.service.js';

export const transactionsRouter = Router();

transactionsRouter.use(requireAuth, recurringCatchUp);

transactionsRouter.get(
  '/',
  validate({ query: listTransactionsQuery }),
  asyncHandler(async (req, res) => {
    res.json(await transactions.list(req.user!, req.query as never));
  }),
);

transactionsRouter.get(
  '/tags',
  asyncHandler(async (req, res) => {
    res.json(await transactions.listTags(req.user!));
  }),
);

transactionsRouter.post(
  '/',
  validate({ body: createTransactionSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await transactions.create(req.user!, req.body));
  }),
);

transactionsRouter.get(
  '/:id',
  validate({ params: transactionIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await transactions.getById(req.user!, req.params.id!));
  }),
);

transactionsRouter.put(
  '/:id',
  validate({ params: transactionIdParam, body: updateTransactionSchema }),
  asyncHandler(async (req, res) => {
    res.json(await transactions.update(req.user!, req.params.id!, req.body));
  }),
);

transactionsRouter.delete(
  '/:id',
  validate({ params: transactionIdParam }),
  asyncHandler(async (req, res) => {
    await transactions.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
