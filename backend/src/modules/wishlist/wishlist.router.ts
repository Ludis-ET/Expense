import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  createWishlistSchema,
  fundWishlistSchema,
  listWishlistQuery,
  promoteWishlistSchema,
  purchaseWishlistSchema,
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

wishlistRouter.post(
  '/:id/fund',
  validate({ params: wishlistIdParam, body: fundWishlistSchema }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.fund(req.user!, req.params.id!, req.body));
  }),
);

wishlistRouter.post(
  '/:id/promote',
  validate({ params: wishlistIdParam, body: promoteWishlistSchema }),
  asyncHandler(async (req, res) => {
    res.json(await wishlist.promoteToGoal(req.user!, req.params.id!, req.body));
  }),
);

wishlistRouter.post(
  '/:id/purchase',
  validate({ params: wishlistIdParam, body: purchaseWishlistSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await wishlist.purchase(req.user!, req.params.id!, req.body));
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
