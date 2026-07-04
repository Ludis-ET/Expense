import { z } from 'zod';
import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import * as currency from '../../core/currency.service.js';

const upsertBody = z.object({
  rates: z
    .array(
      z.object({
        fromCurrency: z.string().length(3),
        toCurrency: z.string().length(3),
        rate: z.coerce.number().positive(),
      }),
    )
    .min(1)
    .max(50),
});

export const exchangeRatesRouter = Router();

exchangeRatesRouter.use(requireAuth);

exchangeRatesRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await currency.listRates(req.user!));
  }),
);

exchangeRatesRouter.put(
  '/',
  validate({ body: upsertBody }),
  asyncHandler(async (req, res) => {
    const body = req.body as z.infer<typeof upsertBody>;
    res.json(await currency.upsertRates(req.user!, body.rates));
  }),
);

exchangeRatesRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await currency.deleteRate(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
