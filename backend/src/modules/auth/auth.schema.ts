import { z } from 'zod';

/**
 * The handful of passwords that show up first in every credential-stuffing
 * list. Deliberately not a complexity rule - forcing a symbol and a digit
 * pushes people towards `Password1!`, which is on this list for a reason.
 * Length plus a blocklist is what actually helps.
 */
const COMMON_PASSWORDS = new Set([
  'password', 'password1', 'password123', '12345678', '123456789', '1234567890',
  'qwerty123', 'qwertyuiop', 'iloveyou', 'admin123', 'welcome1', 'letmein1',
  'abc12345', 'passw0rd', 'santim123', 'football1', 'monkey123', '11111111',
]);

const password = z
  .string()
  .min(10, 'Use at least 10 characters. A short phrase works well.')
  .max(128)
  .refine((p) => !COMMON_PASSWORDS.has(p.toLowerCase()), {
    message: 'That password is one of the most commonly used. Pick another.',
  });

export const registerSchema = z.object({
  name: z.string().min(1).max(200),
  email: z.string().email().toLowerCase(),
  password,
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
