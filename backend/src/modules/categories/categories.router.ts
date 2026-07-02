import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  categoryIdParam,
  createCategorySchema,
  deleteCategoryQuery,
  listCategoriesQuery,
  updateCategorySchema,
} from './categories.schema.js';
import * as categories from './categories.service.js';

export const categoriesRouter = Router();

categoriesRouter.use(requireAuth);

categoriesRouter.get(
  '/',
  validate({ query: listCategoriesQuery }),
  asyncHandler(async (req, res) => {
    res.json(await categories.list(req.user!, req.query.kind as never));
  }),
);

categoriesRouter.post(
  '/',
  validate({ body: createCategorySchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await categories.create(req.user!, req.body));
  }),
);

categoriesRouter.put(
  '/:id',
  validate({ params: categoryIdParam, body: updateCategorySchema }),
  asyncHandler(async (req, res) => {
    res.json(await categories.update(req.user!, req.params.id!, req.body));
  }),
);

categoriesRouter.delete(
  '/:id',
  validate({ params: categoryIdParam, query: deleteCategoryQuery }),
  asyncHandler(async (req, res) => {
    await categories.remove(req.user!, req.params.id!, req.query.reassignTo as string | undefined);
    res.status(204).end();
  }),
);
