/** The authenticated principal attached to each request after JWT verification. */
export interface AuthUser {
  id: string;
  email: string;
}

/**
 * A paired phone, attached instead of a JWT on the ingest routes. It still
 * resolves to a user - `req.user` is populated either way, so services never
 * need to care which credential got the request through.
 */
export interface AuthDevice {
  id: string;
  name: string;
}

// Augment Express's Request so `req.user` is typed everywhere.
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
      device?: AuthDevice;
    }
  }
}

export {};
