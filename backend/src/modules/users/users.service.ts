import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';

const publicUserSelect = {
  id: true,
  name: true,
  email: true,
  role: true,
  locale: true,
  calendar: true,
  orcidId: true,
  orgId: true,
  createdAt: true,
  org: { select: { name: true } },
} as const;

export async function getById(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: publicUserSelect });
  if (!user) throw new NotFoundError('User not found');
  return user;
}

export async function updateProfile(
  userId: string,
  data: { name?: string; locale?: string; orcidId?: string; calendar?: string },
) {
  return prisma.user.update({ where: { id: userId }, data, select: publicUserSelect });
}

/** Lists users within the caller's organization (for team pickers, mentions, etc.). */
export async function listByOrg(orgId: string) {
  return prisma.user.findMany({
    where: { orgId },
    select: { id: true, name: true, email: true, role: true },
    orderBy: { name: 'asc' },
  });
}
