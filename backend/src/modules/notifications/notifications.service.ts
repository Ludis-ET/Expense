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

/** Internal helper other modules can call to push a notification to a user. */
export async function notify(userId: string, type: string, message: string, link?: string) {
  return prisma.notification.create({ data: { userId, type, message, link } });
}
