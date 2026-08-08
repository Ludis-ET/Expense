import { z } from 'zod';
import { AccountType } from '../../core/prisma.js';

const money = z.coerce.number().max(1_000_000_000);

export const createAccountSchema = z.object({
  name: z.string().min(1).max(100),
  type: z.nativeEnum(AccountType).default(AccountType.CASH),
  currency: z.string().length(3).toUpperCase().default('ETB'),
  openingBalance: money.default(0),
  icon: z.string().max(50).optional(),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
  isDefault: z.boolean().optional(),
  /**
   * As the bank writes it, masking and all ("****4821"). Only the last four
   * digits are ever compared, so pasting the masked form straight out of an
   * SMS is enough to make transfer matching work.
   */
  accountNumber: z.string().max(40).nullable().optional(),
});

export const updateAccountSchema = createAccountSchema.partial().extend({
  archived: z.boolean().optional(),
});

export const accountIdParam = z.object({ id: z.string().min(1) });

export type CreateAccountInput = z.infer<typeof createAccountSchema>;
export type UpdateAccountInput = z.infer<typeof updateAccountSchema>;
