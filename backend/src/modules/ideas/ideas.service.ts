import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateIdeaInput, UpdateIdeaInput } from './ideas.schema.js';

// Ideas are visible org-wide: scope by the author's organization.
const orgScope = (orgId: string) => ({ user: { orgId } });

const ideaInclude = {
  user: { select: { id: true, name: true } },
  project: { select: { id: true, title: true } },
} as const;

async function assertOwned(id: string, orgId: string) {
  const idea = await prisma.idea.findFirst({ where: { id, ...orgScope(orgId) } });
  if (!idea) throw new NotFoundError('Idea not found');
  return idea;
}

export async function list(user: AuthUser) {
  return prisma.idea.findMany({
    where: orgScope(user.orgId),
    orderBy: [{ priority: 'desc' }, { createdAt: 'desc' }],
    include: ideaInclude,
  });
}

export async function create(user: AuthUser, input: CreateIdeaInput) {
  if (input.projectId) {
    const project = await prisma.project.findFirst({ where: { id: input.projectId, orgId: user.orgId } });
    if (!project) throw new NotFoundError('Project not found');
  }
  return prisma.idea.create({
    data: { ...input, userId: user.id },
    include: ideaInclude,
  });
}

export async function update(user: AuthUser, id: string, input: UpdateIdeaInput) {
  await assertOwned(id, user.orgId);
  return prisma.idea.update({ where: { id }, data: input, include: ideaInclude });
}

export async function remove(user: AuthUser, id: string) {
  await assertOwned(id, user.orgId);
  await prisma.idea.delete({ where: { id } });
}
