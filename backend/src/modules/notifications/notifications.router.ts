import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import * as notifications from './notifications.service.js';

export const notificationsRouter = Router();

notificationsRouter.use(requireAuth);

notificationsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await notifications.list(req.user!));
  }),
);

notificationsRouter.post(
  '/read-all',
  asyncHandler(async (req, res) => {
    await notifications.markAllRead(req.user!);
    res.status(204).end();
  }),
);

notificationsRouter.post(
  '/:id/read',
  validate({ params: z.object({ id: z.string().min(1) }) }),
  asyncHandler(async (req, res) => {
    await notifications.markRead(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
