import type { RequestHandler } from 'express';
import { z, type ZodTypeAny } from 'zod';
import { BadRequestError } from '../errors.js';

interface Schemas {
  body?: ZodTypeAny;
  query?: ZodTypeAny;
  params?: ZodTypeAny;
}

/**
 * Validates and coerces `req.body`, `req.query`, and `req.params` against the
 * given Zod schemas. On success the parsed values replace the originals so
 * handlers receive typed, sanitized input.
 */
export function validate(schemas: Schemas): RequestHandler {
  return (req, _res, next) => {
    try {
      if (schemas.body) req.body = schemas.body.parse(req.body);
      if (schemas.params) req.params = schemas.params.parse(req.params);
      if (schemas.query) {
        // Express defines `req.query` as a getter that re-parses the URL on every
        // access, so a plain assignment/Object.assign would not persist the coerced
        // values. Replace it with a static data property for the rest of the request.
        const parsed = schemas.query.parse(req.query);
        Object.defineProperty(req, 'query', { value: parsed, writable: true, configurable: true });
      }
      next();
    } catch (err) {
      if (err instanceof z.ZodError) {
        throw new BadRequestError('Validation failed', err.flatten());
      }
      throw err;
    }
  };
}
