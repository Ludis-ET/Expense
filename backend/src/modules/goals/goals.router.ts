import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  contributionParams,
  createContributionSchema,
  createGoalSchema,
  goalIdParam,
  updateGoalSchema,
} from './goals.schema.js';
import * as goals from './goals.service.js';

export const goalsRouter = Router();

goalsRouter.use(requireAuth);

goalsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await goals.list(req.user!));
  }),
);

goalsRouter.post(
  '/',
  validate({ body: createGoalSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await goals.create(req.user!, req.body));
  }),
);

goalsRouter.put(
  '/:id',
  validate({ params: goalIdParam, body: updateGoalSchema }),
  asyncHandler(async (req, res) => {
    res.json(await goals.update(req.user!, req.params.id!, req.body));
  }),
);

goalsRouter.delete(
  '/:id',
  validate({ params: goalIdParam }),
  asyncHandler(async (req, res) => {
    await goals.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);

goalsRouter.post(
  '/:id/contributions',
  validate({ params: goalIdParam, body: createContributionSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await goals.addContribution(req.user!, req.params.id!, req.body));
  }),
);

goalsRouter.delete(
  '/:id/contributions/:cid',
  validate({ params: contributionParams }),
  asyncHandler(async (req, res) => {
    await goals.removeContribution(req.user!, req.params.id!, req.params.cid!);
    res.status(204).end();
  }),
);
