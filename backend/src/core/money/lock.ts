/**
 * Serialising money writes.
 *
 * Every balance guard in Santim is a check followed by a write. Without a lock
 * that pattern is a lie: two requests can both read "500 available", both pass,
 * and both spend it. An offline queue draining after a flight makes this ordinary
 * rather than exotic - the phone fires its backlog as fast as the network allows.
 *
 * A Postgres transaction-scoped advisory lock, taken per user, fixes all of it in
 * one line. Money writes are rare per user and short, so the contention cost is
 * nil, and the lock releases with the transaction whatever happens - including a
 * crash, which a table-based lock could not promise.
 */
import { Prisma } from '../prisma.js';
import { prisma } from '../db.js';

/** A Prisma client scoped to an open transaction. */
export type MoneyTx = Prisma.TransactionClient;

/**
 * Namespace for our advisory locks, so a lock id can never collide with one
 * taken by something else sharing the database.
 */
const LOCK_NAMESPACE = 8_312_004;

/**
 * Money operations do several aggregate reads before writing. The default 5s
 * budget is tight for a user with a long history on a cold cache.
 */
const TIMEOUT_MS = 20_000;
const MAX_WAIT_MS = 15_000;

/**
 * Run `fn` with exclusive access to one user's money, inside a single database
 * transaction. Anything the callback writes is rolled back together if it throws,
 * and no other money write for that user can interleave.
 *
 * Nest-safe: pass an existing `MoneyTx` as `existing` and the callback simply
 * joins the transaction already in progress rather than deadlocking on itself.
 */
export async function withMoneyLock<T>(
  userId: string,
  fn: (tx: MoneyTx) => Promise<T>,
  existing?: MoneyTx,
): Promise<T> {
  if (existing) return fn(existing);

  return prisma.$transaction(
    async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(${LOCK_NAMESPACE}, hashtext(${userId}))`;
      return fn(tx);
    },
    { timeout: TIMEOUT_MS, maxWait: MAX_WAIT_MS },
  );
}
