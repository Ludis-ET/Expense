import { z } from 'zod';

const money = z.coerce.number().positive().max(1_000_000_000);

export const createGoalSchema = z.object({
  name: z.string().min(1).max(100),
  icon: z.string().max(50).optional(),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
  targetAmount: money,
  deadline: z.coerce.date().optional(),
  note: z.string().max(2000).optional(),
});

export const updateGoalSchema = createGoalSchema.partial();

export const createContributionSchema = z.object({
  amount: money,
  date: z.coerce.date().optional(),
  note: z.string().max(500).optional(),
});

export const goalIdParam = z.object({ id: z.string().min(1) });
export const contributionParams = z.object({ id: z.string().min(1), cid: z.string().min(1) });

export type CreateGoalInput = z.infer<typeof createGoalSchema>;
export type UpdateGoalInput = z.infer<typeof updateGoalSchema>;
export type CreateContributionInput = z.infer<typeof createContributionSchema>;
