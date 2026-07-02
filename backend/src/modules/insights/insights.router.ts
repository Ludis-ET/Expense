import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import * as insights from './insights.service.js';

export const insightsRouter = Router();

insightsRouter.use(requireAuth);

insightsRouter.get(
  '/network',
  asyncHandler(async (req, res) => {
    res.json(await insights.network(req.user!));
  }),
);

insightsRouter.get(
  '/burn-rate',
  asyncHandler(async (req, res) => {
    res.json(await insights.burnRate(req.user!));
  }),
);

insightsRouter.get(
  '/impact',
  asyncHandler(async (req, res) => {
    res.json(await insights.impact(req.user!));
  }),
);
