import { z } from 'zod';
import { CategoryKind } from '@prisma/client';

export const createCategorySchema = z.object({
  name: z.string().min(1).max(60),
  kind: z.nativeEnum(CategoryKind),
  icon: z.string().max(50).default('circle'),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/).default('#64748b'),
});

export const updateCategorySchema = z.object({
  name: z.string().min(1).max(60).optional(),
  icon: z.string().max(50).optional(),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
  archived: z.boolean().optional(),
});

export const listCategoriesQuery = z.object({
  kind: z.nativeEnum(CategoryKind).optional(),
});

export const deleteCategoryQuery = z.object({
  reassignTo: z.string().optional(),
});

export const categoryIdParam = z.object({ id: z.string().min(1) });

export type CreateCategoryInput = z.infer<typeof createCategorySchema>;
export type UpdateCategoryInput = z.infer<typeof updateCategorySchema>;
