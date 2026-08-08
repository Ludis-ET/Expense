import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { AVATAR_IDS, BANNER_IDS } from './profile-presets.js';
import * as usersService from './users.service.js';

export const usersRouter = Router();

usersRouter.use(requireAuth);

usersRouter.get(
  '/me',
  asyncHandler(async (req, res) => {
    res.json(await usersService.getById(req.user!.id));
  }),
);

usersRouter.get(
  '/presets',
  asyncHandler(async (_req, res) => {
    res.json({ avatars: AVATAR_IDS, banners: BANNER_IDS });
  }),
);

const updateMeSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  locale: z.string().min(2).max(10).optional(),
  calendar: z.enum(['gregorian', 'ethiopian']).optional(),
  currency: z.string().length(3).toUpperCase().optional(),
  firstDayOfWeek: z.number().int().min(0).max(1).optional(),
  avatarId: z.enum(AVATAR_IDS).optional(),
  bannerId: z.enum(BANNER_IDS).optional(),
  /** Which wallet holds physical cash; ATM withdrawals transfer into it. */
  cashAccountId: z.string().min(1).nullable().optional(),
});

usersRouter.put(
  '/me',
  validate({ body: updateMeSchema }),
  asyncHandler(async (req, res) => {
    res.json(await usersService.updateProfile(req.user!.id, req.body));
  }),
);
