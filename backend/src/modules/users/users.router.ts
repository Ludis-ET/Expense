import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import * as usersService from './users.service.js';

export const usersRouter = Router();

usersRouter.use(requireAuth);

usersRouter.get(
  '/me',
  asyncHandler(async (req, res) => {
    res.json(await usersService.getById(req.user!.id));
  }),
);

// Org-scoped directory — used by team pickers and assignment dropdowns.
usersRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await usersService.listByOrg(req.user!.orgId));
  }),
);

const updateMeSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  locale: z.string().min(2).max(10).optional(),
  calendar: z.enum(['gregorian', 'ethiopian']).optional(),
  orcidId: z.string().regex(/^\d{4}-\d{4}-\d{4}-\d{3}[\dX]$/, 'Invalid ORCID iD format').optional(),
});

usersRouter.put(
  '/me',
  validate({ body: updateMeSchema }),
  asyncHandler(async (req, res) => {
    res.json(await usersService.updateProfile(req.user!.id, req.body));
  }),
);
