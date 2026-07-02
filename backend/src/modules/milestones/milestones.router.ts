import { Router } from 'express';
import { z } from 'zod';
import { MilestoneStatus } from '@prisma/client';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import * as milestones from './milestones.service.js';

export const milestonesRouter = Router();

milestonesRouter.use(requireAuth);

const createSchema = z.object({
  projectId: z.string().min(1),
  description: z.string().min(1).max(500),
  dueDate: z.coerce.date().optional(),
});

const updateSchema = z.object({
  description: z.string().min(1).max(500).optional(),
  dueDate: z.coerce.date().nullable().optional(),
  status: z.nativeEnum(MilestoneStatus).optional(),
});

const idParam = z.object({ id: z.string().min(1) });

milestonesRouter.post(
  '/',
  validate({ body: createSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await milestones.create(req.user!, req.body));
  }),
);

milestonesRouter.patch(
  '/:id',
  validate({ params: idParam, body: updateSchema }),
  asyncHandler(async (req, res) => {
    res.json(await milestones.update(req.user!, req.params.id, req.body));
  }),
);

milestonesRouter.delete(
  '/:id',
  validate({ params: idParam }),
  asyncHandler(async (req, res) => {
    await milestones.remove(req.user!, req.params.id);
    res.status(204).end();
  }),
);
