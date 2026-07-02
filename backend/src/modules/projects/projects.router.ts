import { Router } from 'express';
import { Role } from '@prisma/client';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { requireRole } from '../../core/middleware/rbac.js';
import { validate } from '../../core/middleware/validate.js';
import {
  addTeamMemberSchema,
  createProjectSchema,
  idParam,
  listProjectsSchema,
  updateProjectSchema,
} from './projects.schema.js';
import * as projects from './projects.service.js';

export const projectsRouter = Router();

projectsRouter.use(requireAuth);

projectsRouter.get(
  '/',
  validate({ query: listProjectsSchema }),
  asyncHandler(async (req, res) => {
    res.json(await projects.list(req.user!, req.query as never));
  }),
);

projectsRouter.post(
  '/',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD, Role.RESEARCHER),
  validate({ body: createProjectSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await projects.create(req.user!, req.body));
  }),
);

projectsRouter.get(
  '/:id',
  validate({ params: idParam }),
  asyncHandler(async (req, res) => {
    res.json(await projects.getById(req.user!, req.params.id));
  }),
);

projectsRouter.put(
  '/:id',
  validate({ params: idParam, body: updateProjectSchema }),
  asyncHandler(async (req, res) => {
    res.json(await projects.update(req.user!, req.params.id, req.body));
  }),
);

projectsRouter.delete(
  '/:id',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD),
  validate({ params: idParam }),
  asyncHandler(async (req, res) => {
    await projects.remove(req.user!, req.params.id);
    res.status(204).end();
  }),
);

projectsRouter.post(
  '/:id/team',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD),
  validate({ params: idParam, body: addTeamMemberSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await projects.addTeamMember(req.user!, req.params.id, req.body.userId, req.body.role));
  }),
);

projectsRouter.delete(
  '/:id/team/:userId',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD),
  validate({ params: idParam.extend({ userId: idParam.shape.id }) }),
  asyncHandler(async (req, res) => {
    await projects.removeTeamMember(req.user!, req.params.id, req.params.userId);
    res.status(204).end();
  }),
);
