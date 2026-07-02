import { z } from 'zod';

export const registerSchema = z.object({
  name: z.string().min(1).max(200),
  email: z.string().email().toLowerCase(),
  password: z.string().min(8).max(128),
  // A new user either creates their own workspace, joins one by id, or accepts an invite.
  orgName: z.string().min(1).max(200).optional(),
  orgId: z.string().optional(),
  inviteToken: z.string().optional(),
  locale: z.string().min(2).max(10).default('en'),
}).refine((d) => d.orgName || d.orgId || d.inviteToken, {
  message: 'Provide orgName (to create a workspace), orgId, or inviteToken',
  path: ['orgName'],
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
