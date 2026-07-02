import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { MilestoneStatus } from '@prisma/client';

async function assertOwnedProject(projectId: string, orgId: string) {
  const project = await prisma.project.findFirst({ where: { id: projectId, orgId } });
  if (!project) throw new NotFoundError('Project not found');
}

async function assertOwnedMilestone(id: string, orgId: string) {
  const milestone = await prisma.milestone.findFirst({ where: { id, project: { orgId } } });
  if (!milestone) throw new NotFoundError('Milestone not found');
  return milestone;
}

export async function create(
  user: AuthUser,
  input: { projectId: string; description: string; dueDate?: Date },
) {
  await assertOwnedProject(input.projectId, user.orgId);
  return prisma.milestone.create({ data: input });
}

export async function update(
  user: AuthUser,
  id: string,
  input: { description?: string; dueDate?: Date | null; status?: MilestoneStatus },
) {
  await assertOwnedMilestone(id, user.orgId);
  // Stamp completedDate automatically when a milestone is marked DONE.
  const completedDate = input.status === 'DONE' ? new Date() : input.status ? null : undefined;
  return prisma.milestone.update({ where: { id }, data: { ...input, completedDate } });
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedMilestone(id, user.orgId);
  await prisma.milestone.delete({ where: { id } });
}
