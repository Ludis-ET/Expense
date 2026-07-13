import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import * as guides from './guides.service.js';

export const guidesRouter = Router();

guidesRouter.use(requireAuth);

guidesRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await guides.overview(req.user!));
  }),
);

guidesRouter.get(
  '/for-you',
  asyncHandler(async (req, res) => {
    res.json({ suggestions: await guides.forYou(req.user!) });
  }),
);
