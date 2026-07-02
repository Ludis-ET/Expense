import { Router } from 'express';
import { z } from 'zod';
import { Role } from '@prisma/client';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { requireRole } from '../../core/middleware/rbac.js';
import { validate } from '../../core/middleware/validate.js';
import * as invitations from './invitations.service.js';

export const invitationsRouter = Router();

// Public: invite-info lookup for the accept page (no auth).
invitationsRouter.get(
  '/info/:token',
  validate({ params: z.object({ token: z.string().min(1) }) }),
  asyncHandler(async (req, res) => {
    res.json(await invitations.info(req.params.token));
  }),
);

// Everything below requires auth.
invitationsRouter.use(requireAuth);

invitationsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await invitations.list(req.user!.orgId));
  }),
);

invitationsRouter.post(
  '/',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD),
  validate({
    body: z.object({
      email: z.string().email(),
      role: z.nativeEnum(Role).default(Role.RESEARCHER),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await invitations.create(req.user!, req.body.email, req.body.role));
  }),
);

invitationsRouter.delete(
  '/:id',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD),
  validate({ params: z.object({ id: z.string().min(1) }) }),
  asyncHandler(async (req, res) => {
    await invitations.revoke(req.user!, req.params.id);
    res.status(204).end();
  }),
);
