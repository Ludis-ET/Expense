import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import * as ai from './ai.service.js';
import * as features from './ai.features.js';

export const aiRouter = Router();

aiRouter.use(requireAuth);

// --- Provider settings (priority order + keys) ---

aiRouter.get(
  '/settings',
  asyncHandler(async (req, res) => {
    res.json(await ai.getSettings(req.user!.id));
  }),
);

const providerUpdateSchema = z.object({
  providers: z
    .array(
      z.object({
        id: z.enum(['anthropic', 'openai', 'google']),
        model: z.string().max(100).optional(),
        enabled: z.boolean(),
        apiKey: z.string().max(400).optional(),
      }),
    )
    .max(10),
});

aiRouter.put(
  '/settings',
  validate({ body: providerUpdateSchema }),
  asyncHandler(async (req, res) => {
    res.json(await ai.updateSettings(req.user!.id, req.body.providers));
  }),
);

aiRouter.post(
  '/settings/test',
  validate({ body: z.object({ id: z.enum(['anthropic', 'openai', 'google']) }) }),
  asyncHandler(async (req, res) => {
    res.json(await ai.testProvider(req.user!.id, req.body.id));
  }),
);

aiRouter.get(
  '/status',
  asyncHandler(async (req, res) => {
    res.json({ configured: await ai.hasProvider(req.user!.id) });
  }),
);

// --- Features ---

aiRouter.post(
  '/ask',
  validate({ body: z.object({ question: z.string().min(2).max(500) }) }),
  asyncHandler(async (req, res) => {
    res.json(await features.ask(req.user!, req.body.question));
  }),
);

aiRouter.post(
  '/review',
  validate({
    body: z.object({
      month: z.string().regex(/^\d{4}-\d{2}$/, 'Expected YYYY-MM'),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await features.monthlyReview(req.user!, req.body.month));
  }),
);

aiRouter.post(
  '/categorize',
  validate({
    body: z.object({
      description: z.string().min(2).max(500),
      amount: z.coerce.number().positive().optional(),
      payee: z.string().max(200).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await features.categorize(req.user!, req.body.description, req.body.amount, req.body.payee));
  }),
);
