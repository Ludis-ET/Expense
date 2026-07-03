import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  acceptSchema,
  accountIdParam,
  createHouseholdSchema,
  inviteSchema,
  shareSchema,
} from './household.schema.js';
import * as household from './household.service.js';

export const householdRouter = Router();

householdRouter.use(requireAuth);

householdRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await household.overview(req.user!));
  }),
);

householdRouter.get(
  '/invites',
  asyncHandler(async (req, res) => {
    const items = await household.pendingInvitesForUser(req.user!.email);
    res.json({
      items: items.map((i) => ({
        id: i.id,
        token: i.token,
        householdName: i.household.name,
        invitedBy: i.invitedBy.name,
        expiresAt: i.expiresAt,
      })),
    });
  }),
);

householdRouter.post(
  '/',
  validate({ body: createHouseholdSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await household.create(req.user!, req.body.name));
  }),
);

householdRouter.post(
  '/invite',
  validate({ body: inviteSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await household.invite(req.user!, req.body.email));
  }),
);

householdRouter.post(
  '/accept',
  validate({ body: acceptSchema }),
  asyncHandler(async (req, res) => {
    res.json(await household.acceptInvite(req.user!, req.body.token));
  }),
);

householdRouter.post(
  '/leave',
  asyncHandler(async (req, res) => {
    res.json(await household.leave(req.user!));
  }),
);

householdRouter.put(
  '/accounts/:accountId/share',
  validate({ params: accountIdParam, body: shareSchema }),
  asyncHandler(async (req, res) => {
    res.json(await household.shareAccount(req.user!, req.params.accountId!, req.body.shared));
  }),
);
