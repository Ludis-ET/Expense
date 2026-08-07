import { prisma } from '../../core/db.js';
import { NotFoundError, BadRequestError } from '../../core/errors.js';
import { isAvatarId, isBannerId } from './profile-presets.js';

const publicUserSelect = {
  id: true,
  name: true,
  email: true,
  locale: true,
  calendar: true,
  currency: true,
  firstDayOfWeek: true,
  avatarId: true,
  bannerId: true,
  createdAt: true,
} as const;

export type UpdateProfileInput = {
  name?: string;
  locale?: string;
  calendar?: string;
  currency?: string;
  firstDayOfWeek?: number;
  avatarId?: string;
  bannerId?: string;
};

export async function getById(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: publicUserSelect });
  if (!user) throw new NotFoundError('User not found');
  return user;
}

export async function updateProfile(userId: string, data: UpdateProfileInput) {
  if (data.avatarId !== undefined && !isAvatarId(data.avatarId)) {
    throw new BadRequestError('Unknown avatar');
  }
  if (data.bannerId !== undefined && !isBannerId(data.bannerId)) {
    throw new BadRequestError('Unknown banner');
  }
  return prisma.user.update({ where: { id: userId }, data, select: publicUserSelect });
}
