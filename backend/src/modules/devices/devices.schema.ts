import { z } from 'zod';

export const pairDeviceSchema = z.object({
  name: z.string().min(1).max(80),
  platform: z.string().min(1).max(32).default('android'),
  appVersion: z.string().max(32).optional(),
});

export const deviceIdParam = z.object({ id: z.string().min(1) });

export type PairDeviceInput = z.infer<typeof pairDeviceSchema>;
