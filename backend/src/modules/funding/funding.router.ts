import { Router } from 'express';
import { Prisma } from '../../core/prisma.js';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  createFundingRuleSchema,
  fundingRuleIdParam,
  runFundingRuleSchema,
  updateFundingRuleSchema,
} from './funding.schema.js';
import * as funding from './funding.service.js';

export const fundingRouter = Router();

fundingRouter.use(requireAuth);

fundingRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await funding.list(req.user!));
  }),
);

fundingRouter.get(
  '/:id',
  validate({ params: fundingRuleIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await funding.getById(req.user!, req.params.id!));
  }),
);

/** What this rule would do right now, without doing it. */
fundingRouter.get(
  '/:id/preview',
  validate({ params: fundingRuleIdParam }),
  asyncHandler(async (req, res) => {
    const accountId = typeof req.query.accountId === 'string' ? req.query.accountId : undefined;
    const basis = typeof req.query.basis === 'string' ? new Prisma.Decimal(req.query.basis) : undefined;
    res.json(await funding.preview(req.user!, req.params.id!, { accountId, basis }));
  }),
);

fundingRouter.post(
  '/',
  validate({ body: createFundingRuleSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await funding.create(req.user!, req.body));
  }),
);

fundingRouter.put(
  '/:id',
  validate({ params: fundingRuleIdParam, body: updateFundingRuleSchema }),
  asyncHandler(async (req, res) => {
    res.json(await funding.update(req.user!, req.params.id!, req.body));
  }),
);

/** Fill the plans for real. */
fundingRouter.post(
  '/:id/run',
  validate({ params: fundingRuleIdParam, body: runFundingRuleSchema }),
  asyncHandler(async (req, res) => {
    const { accountId, basis, clientOpId } = req.body;
    res.json(
      await funding.run(req.user!, req.params.id!, {
        accountId,
        basis: basis !== undefined ? new Prisma.Decimal(basis) : undefined,
        clientOpId,
      }),
    );
  }),
);

fundingRouter.delete(
  '/:id',
  validate({ params: fundingRuleIdParam }),
  asyncHandler(async (req, res) => {
    await funding.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
