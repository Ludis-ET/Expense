import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { search } from './search.service.js';

export const searchRouter = Router();

searchRouter.use(requireAuth);

searchRouter.get(
  '/',
  validate({
    query: z.object({
      q: z.string().min(1).max(120),
      limit: z.coerce.number().int().min(1).max(30).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const q = String(req.query.q ?? '').trim();
    const limit = req.query.limit ? Number(req.query.limit) : 10;
    res.json(await search(req.user!.id, q, limit));
  }),
);
