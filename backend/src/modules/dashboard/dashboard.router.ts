import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import { tabReminderCatchUp } from '../ledger/ledger.middleware.js';
import * as dashboard from './dashboard.service.js';

export const dashboardRouter = Router();

dashboardRouter.use(requireAuth, recurringCatchUp, tabReminderCatchUp);

dashboardRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await dashboard.overview(req.user!));
  }),
);
