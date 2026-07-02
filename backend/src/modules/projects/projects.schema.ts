import { z } from 'zod';
import { ProjectStatus, TeamRole } from '@prisma/client';

const isoDate = z.string().datetime().or(z.coerce.date()).optional();

export const createProjectSchema = z.object({
  title: z.string().min(1).max(300),
  summary: z.string().max(5000).optional(),
  status: z.nativeEnum(ProjectStatus).optional(),
  currency: z.string().length(3).toUpperCase().default('USD'),
  startDate: isoDate,
  endDate: isoDate,
  leadUserId: z.string().optional(),
});

export const updateProjectSchema = createProjectSchema.partial();

export const listProjectsSchema = z.object({
  status: z.nativeEnum(ProjectStatus).optional(),
  mine: z.coerce.boolean().optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

export const idParam = z.object({ id: z.string().min(1) });

export const addTeamMemberSchema = z.object({
  userId: z.string().min(1),
  role: z.nativeEnum(TeamRole).default(TeamRole.COLLABORATOR),
});

export type CreateProjectInput = z.infer<typeof createProjectSchema>;
export type UpdateProjectInput = z.infer<typeof updateProjectSchema>;
export type ListProjectsQuery = z.infer<typeof listProjectsSchema>;
