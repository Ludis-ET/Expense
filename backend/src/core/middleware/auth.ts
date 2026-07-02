import type { RequestHandler } from 'express';
import { UnauthorizedError } from '../errors.js';
import { verifyAccessToken } from '../../modules/auth/jwt.js';

/**
 * Requires a valid `Authorization: Bearer <token>` header and attaches the
 * decoded principal to `req.user`. The principal carries `orgId`, which the
 * service layer uses for tenant scoping.
 */
export const requireAuth: RequestHandler = (req, _res, next) => {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    throw new UnauthorizedError('Missing or malformed Authorization header');
  }
  const token = header.slice('Bearer '.length).trim();
  try {
    req.user = verifyAccessToken(token);
    next();
  } catch {
    throw new UnauthorizedError('Invalid or expired token');
  }
};
