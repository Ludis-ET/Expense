import { z } from 'zod';
import { FundingStepMode } from '../../core/prisma.js';

const money = z.coerce.number().min(0).max(1_000_000_000);

/**
 * One plan's share of an arriving payday.
 *
 * FILL is the default because it is what people mean: top this plan up to what
 * it is meant to hold. FIXED and PERCENT exist for the plans that should take a
 * set slice regardless of what they already have.
 */
const stepSchema = z.object({
  budgetId: z.string().min(1),
  mode: z.nativeEnum(FundingStepMode).default(FundingStepMode.FILL),
  /** Birr for FIXED, a percentage for PERCENT, ignored for FILL. */
  amount: money.default(0),
});

export const createFundingRuleSchema = z.object({
  name: z.string().trim().min(1, 'Give the rule a name').max(80),
  /** Only fire for income landing here. Leave it off for any wallet. */
  accountId: z.string().min(1).nullish(),
  currency: z.string().length(3).default('ETB'),
  /** Ignore anything smaller, so a small refund does not trigger payday. */
  minAmount: money.default(0),
  active: z.boolean().default(true),
  /** Ask before moving money. On by default - silent transfers are alarming. */
  confirmFirst: z.boolean().default(true),
  steps: z.array(stepSchema).min(1, 'Add at least one plan').max(30),
});

export const updateFundingRuleSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  accountId: z.string().min(1).nullable().optional(),
  currency: z.string().length(3).optional(),
  minAmount: money.optional(),
  active: z.boolean().optional(),
  confirmFirst: z.boolean().optional(),
  steps: z.array(stepSchema).min(1).max(30).optional(),
});

export const runFundingRuleSchema = z.object({
  /** Override the wallet, for a payday that landed somewhere unusual. */
  accountId: z.string().min(1).optional(),
  /** The income that triggered this, when there is one. Drives PERCENT steps. */
  basis: z.coerce.number().positive().max(1_000_000_000).optional(),
  clientOpId: z.string().min(1).max(80).nullish(),
});

export const fundingRuleIdParam = z.object({ id: z.string().min(1) });

export type CreateFundingRuleInput = z.infer<typeof createFundingRuleSchema>;
export type UpdateFundingRuleInput = z.infer<typeof updateFundingRuleSchema>;
export type RunFundingRuleInput = z.infer<typeof runFundingRuleSchema>;
