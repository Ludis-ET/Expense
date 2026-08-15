/**
 * "Has anyone run this user's catch-up recently?"
 *
 * The recurring engine and the tab reminders both run lazily off the request
 * path, debounced so a burst of requests does not re-run them. That debounce
 * used to be a module-level `Map<userId, timestamp>` in each middleware, which
 * had two faults: entries were never evicted, so it leaked for the life of the
 * process, and it was per-process, so two replicas would both decide they were
 * the one to run and duplicate the work.
 *
 * A conditional UPDATE settles it. Exactly one caller matches the WHERE clause
 * and gets a row back; everyone else gets zero rows and skips.
 */
import { prisma } from './db.js';
import { logger } from './logger.js';

const DEBOUNCE_MS = 5 * 60 * 1000;

/**
 * Which sweep is claiming. They get their own stamps because they hang off
 * different routers - a shared one would let whichever ran first block the
 * other for the rest of the window.
 */
export type SweepKind = 'lastCatchUpAt' | 'lastReminderSyncAt';

/**
 * Try to become the one that runs this sweep for this user.
 *
 * Returns true at most once per debounce window across every replica.
 */
export async function claimSweep(
  userId: string,
  kind: SweepKind,
  now = new Date(),
): Promise<boolean> {
  const cutoff = new Date(now.getTime() - DEBOUNCE_MS);
  const { count } = await prisma.user.updateMany({
    where: {
      id: userId,
      OR: [{ [kind]: null }, { [kind]: { lt: cutoff } }],
    },
    data: { [kind]: now },
  });
  return count > 0;
}

/**
 * Hand the claim back after a failure, so the next request can retry rather
 * than waiting out the full window on work that never happened.
 */
export async function releaseSweep(userId: string, kind: SweepKind): Promise<void> {
  await prisma.user
    .update({ where: { id: userId }, data: { [kind]: null } })
    .catch(() => {
      // The user may have been deleted mid-flight. Nothing to release.
    });
}

/**
 * Shared body for the lazy sweep middlewares: claim, run, release on failure.
 * Fire-and-forget by design - the response must not wait on it.
 */
export function runClaimed(
  userId: string,
  kind: SweepKind,
  label: string,
  work: (userId: string) => Promise<unknown>,
): void {
  void claimSweep(userId, kind)
    .then(async (won) => {
      if (!won) return;
      try {
        await work(userId);
      } catch (err) {
        await releaseSweep(userId, kind);
        logger.error({ err, userId }, `${label} failed`);
      }
    })
    .catch((err: unknown) => logger.error({ err, userId }, `${label} claim failed`));
}
