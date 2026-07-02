import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { recurringCatchUp } from './recurring.middleware.js';
import { createRecurringSchema, recurringIdParam, updateRecurringSchema } from './recurring.schema.js';
import * as recurring from './recurring.service.js';

export const recurringRouter = Router();

recurringRouter.use(requireAuth, recurringCatchUp);

recurringRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await recurring.list(req.user!));
  }),
);

recurringRouter.post(
  '/',
  validate({ body: createRecurringSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await recurring.create(req.user!, req.body));
  }),
);

recurringRouter.put(
  '/:id',
  validate({ params: recurringIdParam, body: updateRecurringSchema }),
  asyncHandler(async (req, res) => {
    res.json(await recurring.update(req.user!, req.params.id!, req.body));
  }),
);

recurringRouter.delete(
  '/:id',
  validate({ params: recurringIdParam }),
  asyncHandler(async (req, res) => {
    await recurring.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);

recurringRouter.post(
  '/:id/run-now',
  validate({ params: recurringIdParam }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await recurring.runNow(req.user!, req.params.id!));
  }),
);
