import { z } from 'zod';
import { IdeaStatus } from '@prisma/client';

export const createIdeaSchema = z.object({
  title: z.string().min(1).max(300),
  description: z.string().max(5000).optional(),
  priority: z.coerce.number().int().min(0).max(5).default(0),
  projectId: z.string().optional(),
});

export const updateIdeaSchema = z.object({
  title: z.string().min(1).max(300).optional(),
  description: z.string().max(5000).optional(),
  priority: z.coerce.number().int().min(0).max(5).optional(),
  status: z.nativeEnum(IdeaStatus).optional(),
  projectId: z.string().nullable().optional(),
});

export const idParam = z.object({ id: z.string().min(1) });

export type CreateIdeaInput = z.infer<typeof createIdeaSchema>;
export type UpdateIdeaInput = z.infer<typeof updateIdeaSchema>;
