import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  createWishlistSchema,
  listWishlistQuery,
  planWishlistSchema,
  updateWishlistSchema,
  wishlistIdParam,
} from './wishlist.schema.js';
import * as wishlist from './wishlist.service.js';

export const wishlistRouter = Router();

wishlistRouter.use(requireAuth);

wishlistRouter.get(
  '/',
  validate({ query: listWishlistQuery }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.list(req.user!, req.query as never));
  }),
);

wishlistRouter.get(
  '/:id',
  validate({ params: wishlistIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.getById(req.user!, req.params.id!));
  }),
);

wishlistRouter.post(
  '/',
  validate({ body: createWishlistSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await wishlist.create(req.user!, req.body));
  }),
);

wishlistRouter.put(
  '/:id',
  validate({ params: wishlistIdParam, body: updateWishlistSchema }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.update(req.user!, req.params.id!, req.body));
  }),
);

/** Turn a want into a budget plan and link the two. */
wishlistRouter.post(
  '/:id/plan',
  validate({ params: wishlistIdParam, body: planWishlistSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await wishlist.plan(req.user!, req.params.id!, req.body));
  }),
);

wishlistRouter.post(
  '/:id/unlink-plan',
  validate({ params: wishlistIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.unlinkPlan(req.user!, req.params.id!));
  }),
);

wishlistRouter.post(
  '/:id/bought',
  validate({ params: wishlistIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.markBought(req.user!, req.params.id!));
  }),
);

wishlistRouter.delete(
  '/:id',
  validate({ params: wishlistIdParam }),
  asyncHandler(async (req, res) => {
    await wishlist.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
