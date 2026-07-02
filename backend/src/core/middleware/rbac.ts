import type { RequestHandler } from 'express';
import type { Role } from '@prisma/client';
import { ForbiddenError, UnauthorizedError } from '../errors.js';

/**
 * Role-Based Access Control. Allows the request only if the authenticated
 * user's role is in `allowed`. Must run after `requireAuth`.
 */
export function requireRole(...allowed: Role[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) throw new UnauthorizedError();
    if (!allowed.includes(req.user.role)) {
      throw new ForbiddenError(`Requires one of roles: ${allowed.join(', ')}`);
    }
    next();
  };
}
