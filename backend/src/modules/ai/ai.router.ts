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
  '/report',
  validate({
    body: z.object({
      projectId: z.string().min(1),
      type: z.enum(['progress', 'funder', 'proposal']).default('progress'),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await features.writeReport(req.user!, req.body.projectId, req.body.type));
  }),
);

aiRouter.post(
  '/extract',
  validate({ body: z.object({ text: z.string().min(10).max(8000) }) }),
  asyncHandler(async (req, res) => {
    res.json(await features.extract(req.user!, req.body.text));
  }),
);
