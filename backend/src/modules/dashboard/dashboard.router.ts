import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import * as dashboard from './dashboard.service.js';

export const dashboardRouter = Router();

dashboardRouter.use(requireAuth);

dashboardRouter.get(
  '/stats',
  asyncHandler(async (req, res) => {
    res.json(await dashboard.getStats(req.user!));
  }),
);
