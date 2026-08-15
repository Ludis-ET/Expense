import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';

export async function list(user: AuthUser) {
  const [items, unread] = await Promise.all([
    prisma.notification.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: 50,
    }),
    prisma.notification.count({ where: { userId: user.id, readFlag: false } }),
  ]);
  return { items, unread };
}

export async function markRead(user: AuthUser, id: string) {
  // updateMany scopes by userId so a user can only touch their own notifications.
  await prisma.notification.updateMany({ where: { id, userId: user.id }, data: { readFlag: true } });
}

export async function markAllRead(user: AuthUser) {
  await prisma.notification.updateMany({ where: { userId: user.id, readFlag: false }, data: { readFlag: true } });
}

/**
 * Push a notification to a user.
 *
 * `dedupeKey` identifies the *thing being announced*, not the row. Pass one for
 * anything a background sweep can rediscover - a due rule, an overdue tab - and
 * repeats update the existing row and mark it unread again instead of stacking.
 * Without it a dormant recurring rule could file 120 notifications in a single
 * catch-up and push every real alert out of the 50-row window the app reads.
 *
 * Omit it for genuine one-off events, which should stack.
 */
export async function notify(
  userId: string,
  type: string,
  message: string,
  link?: string,
  dedupeKey?: string,
  opts: {
    /**
     * Whether a repeat should mark the notification unread again.
     *
     * True for something that has genuinely changed - a rule falling further
     * behind is news even if the last notice was read. False when the key
     * already carries the period it covers, as the tab reminders do: within
     * one week it is the same announcement, and re-surfacing it every time the
     * five-minute sweep runs would be nagging, not informing.
     */
    resurface?: boolean;
  } = {},
) {
  if (!dedupeKey) {
    return prisma.notification.create({ data: { userId, type, message, link } });
  }
  const resurface = opts.resurface ?? true;
  return prisma.notification.upsert({
    where: { userId_dedupeKey: { userId, dedupeKey } },
    create: { userId, type, message, link, dedupeKey },
    update: { message, link, ...(resurface ? { readFlag: false } : {}) },
  });
}

/**
 * Retention sweep. Read notifications older than this are noise - the app only
 * ever renders the newest 50, so everything behind that is invisible weight.
 */
const RETENTION_DAYS = 90;

export async function pruneOld(userId: string) {
  const cutoff = new Date(Date.now() - RETENTION_DAYS * 86_400_000);
  const { count } = await prisma.notification.deleteMany({
    where: { userId, readFlag: true, createdAt: { lt: cutoff } },
  });
  return count;
}
