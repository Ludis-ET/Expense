import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { deviceIdParam, pairDeviceSchema } from './devices.schema.js';
import * as devices from './devices.service.js';

export const devicesRouter = Router();

devicesRouter.use(requireAuth);

devicesRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await devices.list(req.user!));
  }),
);

/** Pairs the phone the user is signed in on and hands back its token, once. */
devicesRouter.post(
  '/',
  validate({ body: pairDeviceSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await devices.pair(req.user!, req.body));
  }),
);

devicesRouter.post(
  '/:id/revoke',
  validate({ params: deviceIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await devices.revoke(req.user!, req.params.id!));
  }),
);

devicesRouter.delete(
  '/:id',
  validate({ params: deviceIdParam }),
  asyncHandler(async (req, res) => {
    await devices.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
