import type { Role } from '@prisma/client';

/** The authenticated principal attached to each request after JWT verification. */
export interface AuthUser {
  id: string;
  email: string;
  role: Role;
  /** Tenant scope — the organization the user belongs to. */
  orgId: string;
}

// Augment Express's Request so `req.user` is typed everywhere.
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export {};
