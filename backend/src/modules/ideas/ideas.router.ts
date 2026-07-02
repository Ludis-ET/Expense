import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { createIdeaSchema, idParam, updateIdeaSchema } from './ideas.schema.js';
import * as ideas from './ideas.service.js';

export const ideasRouter = Router();

ideasRouter.use(requireAuth);

ideasRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await ideas.list(req.user!));
  }),
);

ideasRouter.post(
  '/',
  validate({ body: createIdeaSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await ideas.create(req.user!, req.body));
  }),
);

ideasRouter.patch(
  '/:id',
  validate({ params: idParam, body: updateIdeaSchema }),
  asyncHandler(async (req, res) => {
    res.json(await ideas.update(req.user!, req.params.id, req.body));
  }),
);

ideasRouter.delete(
  '/:id',
  validate({ params: idParam }),
  asyncHandler(async (req, res) => {
    await ideas.remove(req.user!, req.params.id);
    res.status(204).end();
  }),
);
