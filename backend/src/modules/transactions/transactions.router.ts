import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import {
  createTransactionSchema,
  exportTransactionsQuery,
  listTransactionsQuery,
  transactionIdParam,
  updateTransactionSchema,
} from './transactions.schema.js';
import * as transactions from './transactions.service.js';
import { exportPreview, streamExport } from './transactions.export.js';

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

/**
 * How much a download would contain. Lets the sheet say "1,284 transactions,
 * about 160 KB" before anyone commits to it.
 */
transactionsRouter.get(
  '/export/preview',
  validate({ query: exportTransactionsQuery }),
  asyncHandler(async (req, res) => {
    const query = req.query as never as import('./transactions.schema.js').ExportTransactionsQuery;
    res.json(await exportPreview(transactions.buildWhere(req.user!, query)));
  }),
);

/**
 * The download itself, streamed.
 *
 * Declared before `/:id` or Express would read "export" as a transaction id.
 */
transactionsRouter.get(
  '/export',
  validate({ query: exportTransactionsQuery }),
  asyncHandler(async (req, res) => {
    const query = req.query as never as import('./transactions.schema.js').ExportTransactionsQuery;
    await streamExport(req.user!, query, transactions.buildWhere(req.user!, query), res);
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
