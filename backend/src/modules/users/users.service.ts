import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';

const publicUserSelect = {
  id: true,
  name: true,
  email: true,
  locale: true,
  calendar: true,
  currency: true,
  firstDayOfWeek: true,
  createdAt: true,
} as const;

export async function getById(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: publicUserSelect });
  if (!user) throw new NotFoundError('User not found');
  return user;
}

export async function updateProfile(
  userId: string,
  data: { name?: string; locale?: string; calendar?: string; currency?: string; firstDayOfWeek?: number },
) {
  return prisma.user.update({ where: { id: userId }, data, select: publicUserSelect });
}
