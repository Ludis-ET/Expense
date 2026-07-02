import { z } from 'zod';

export const registerSchema = z.object({
  name: z.string().min(1).max(200),
  email: z.string().email().toLowerCase(),
  password: z.string().min(8).max(128),
  locale: z.string().min(2).max(10).default('en'),
});

export const loginSchema = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(1),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type RefreshInput = z.infer<typeof refreshSchema>;
