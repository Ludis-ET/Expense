import { TeamRole } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateProjectInput, ListProjectsQuery, UpdateProjectInput } from './projects.schema.js';

/**
 * Loads a project but only if it belongs to the caller's organization.
 * This is the central tenant-isolation check reused by every project operation.
 */
async function findOwnedProject(id: string, orgId: string) {
  const project = await prisma.project.findFirst({ where: { id, orgId } });
  if (!project) throw new NotFoundError('Project not found');
  return project;
}

export async function list(user: AuthUser, query: ListProjectsQuery) {
  const where = {
    orgId: user.orgId,
    ...(query.status ? { status: query.status } : {}),
    ...(query.mine ? { team: { some: { userId: user.id } } } : {}),
  };

  const [total, items] = await Promise.all([
    prisma.project.count({ where }),
    prisma.project.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (query.page - 1) * query.pageSize,
      take: query.pageSize,
      include: { _count: { select: { team: true, milestones: true, budgetItems: true } } },
    }),
  ]);

  return { items, total, page: query.page, pageSize: query.pageSize };
}

export async function getById(user: AuthUser, id: string) {
  await findOwnedProject(id, user.orgId);
  return prisma.project.findUnique({
    where: { id },
    include: {
      lead: { select: { id: true, name: true, email: true } },
      team: { include: { user: { select: { id: true, name: true, email: true } } } },
      milestones: { orderBy: { dueDate: 'asc' } },
      budgetItems: true,
    },
  });
}

export async function create(user: AuthUser, input: CreateProjectInput) {
  if (input.leadUserId) await assertSameOrgUser(input.leadUserId, user.orgId);

  return prisma.$transaction(async (tx) => {
    const project = await tx.project.create({
      data: {
        title: input.title,
        summary: input.summary,
        status: input.status,
        currency: input.currency,
        startDate: input.startDate,
        endDate: input.endDate,
        orgId: user.orgId,
        leadUserId: input.leadUserId ?? user.id,
      },
    });

    // The lead (defaulting to the creator) joins the team as PI.
    await tx.teamMember.create({
      data: { projectId: project.id, userId: project.leadUserId!, role: TeamRole.PI },
    });

    return project;
  });
}

export async function update(user: AuthUser, id: string, input: UpdateProjectInput) {
  await findOwnedProject(id, user.orgId);
  if (input.leadUserId) await assertSameOrgUser(input.leadUserId, user.orgId);
  return prisma.project.update({ where: { id }, data: input });
}

export async function remove(user: AuthUser, id: string) {
  await findOwnedProject(id, user.orgId);
  await prisma.project.delete({ where: { id } });
}

export async function addTeamMember(user: AuthUser, projectId: string, userId: string, role: TeamRole) {
  await findOwnedProject(projectId, user.orgId);
  await assertSameOrgUser(userId, user.orgId);
  return prisma.teamMember.upsert({
    where: { projectId_userId: { projectId, userId } },
    create: { projectId, userId, role },
    update: { role },
    include: { user: { select: { id: true, name: true, email: true } } },
  });
}

export async function removeTeamMember(user: AuthUser, projectId: string, userId: string) {
  await findOwnedProject(projectId, user.orgId);
  await prisma.teamMember.delete({ where: { projectId_userId: { projectId, userId } } });
}

async function assertSameOrgUser(userId: string, orgId: string) {
  const target = await prisma.user.findFirst({ where: { id: userId, orgId } });
  if (!target) throw new BadRequestError('User does not belong to your organization');
}
