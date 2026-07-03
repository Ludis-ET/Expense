import { z } from 'zod';

export const createHouseholdSchema = z.object({ name: z.string().min(1).max(80).optional() });
export const inviteSchema = z.object({ email: z.string().email() });
export const acceptSchema = z.object({ token: z.string().min(1) });
export const shareSchema = z.object({ shared: z.boolean() });
export const accountIdParam = z.object({ accountId: z.string().min(1) });
