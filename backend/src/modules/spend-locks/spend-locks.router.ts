import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  createSpendLockSchema,
  listSpendLocksQuery,
  spendLockIdParam,
  updateSpendLockSchema,
} from './spend-locks.schema.js';
import * as locks from './spend-locks.service.js';

export const spendLocksRouter = Router();

spendLocksRouter.use(requireAuth);

spendLocksRouter.get(
  '/',
  validate({ query: listSpendLocksQuery }),
  asyncHandler(async (req, res) => {
    res.json(await locks.list(req.user!, req.query as never));
  }),
);

spendLocksRouter.post(
  '/',
  validate({ body: createSpendLockSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await locks.create(req.user!, req.body));
  }),
);

spendLocksRouter.put(
  '/:id',
  validate({ params: spendLockIdParam, body: updateSpendLockSchema }),
  asyncHandler(async (req, res) => {
    res.json(await locks.update(req.user!, req.params.id!, req.body));
  }),
);

spendLocksRouter.delete(
  '/:id',
  validate({ params: spendLockIdParam }),
  asyncHandler(async (req, res) => {
    await locks.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
