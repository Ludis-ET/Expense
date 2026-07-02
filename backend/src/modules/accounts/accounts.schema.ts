import { z } from 'zod';
import { AccountType } from '@prisma/client';

const money = z.coerce.number().max(1_000_000_000);

export const createAccountSchema = z.object({
  name: z.string().min(1).max(100),
  type: z.nativeEnum(AccountType).default(AccountType.CASH),
  currency: z.string().length(3).toUpperCase().default('ETB'),
  openingBalance: money.default(0),
  icon: z.string().max(50).optional(),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
  isDefault: z.boolean().optional(),
});

export const updateAccountSchema = createAccountSchema.partial().extend({
  archived: z.boolean().optional(),
});

export const accountIdParam = z.object({ id: z.string().min(1) });

export type CreateAccountInput = z.infer<typeof createAccountSchema>;
export type UpdateAccountInput = z.infer<typeof updateAccountSchema>;
