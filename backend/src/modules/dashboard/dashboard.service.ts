import { ExpenseStatus, Prisma } from '@prisma/client';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';

/**
 * Aggregated metrics for the org dashboard. All queries are scoped to the
 * caller's organization, directly or through the project relation.
 */
export async function getStats(user: AuthUser) {
  const { orgId } = user;

  const [projectsByStatus, totalProjects, publications, datasets, openIdeas, pendingExpenses] = await Promise.all([
    prisma.project.groupBy({ by: ['status'], where: { orgId }, _count: { _all: true } }),
    prisma.project.count({ where: { orgId } }),
    prisma.publication.count({ where: { project: { orgId } } }),
    prisma.dataset.count({ where: { project: { orgId } } }),
    prisma.idea.count({ where: { user: { orgId }, status: 'OPEN' } }),
    prisma.expense.count({ where: { status: ExpenseStatus.PENDING, budgetItem: { project: { orgId } } } }),
  ]);

  const plannedAgg = await prisma.budgetItem.aggregate({
    where: { project: { orgId } },
    _sum: { plannedAmount: true },
  });
  const approvedAgg = await prisma.expense.aggregate({
    where: { status: ExpenseStatus.APPROVED, budgetItem: { project: { orgId } } },
    _sum: { amount: true },
  });

  const totalPlanned = plannedAgg._sum.plannedAmount ?? new Prisma.Decimal(0);
  const totalSpent = approvedAgg._sum.amount ?? new Prisma.Decimal(0);

  const recentProjects = await prisma.project.findMany({
    where: { orgId },
    orderBy: { updatedAt: 'desc' },
    take: 5,
    select: { id: true, title: true, status: true, currency: true, updatedAt: true },
  });

  const upcomingMilestones = await prisma.milestone.findMany({
    where: { project: { orgId }, status: { not: 'DONE' }, dueDate: { not: null } },
    orderBy: { dueDate: 'asc' },
    take: 5,
    include: { project: { select: { id: true, title: true } } },
  });

  return {
    counts: {
      projects: totalProjects,
      publications,
      datasets,
      openIdeas,
      pendingExpenses,
    },
    projectsByStatus: projectsByStatus.map((g) => ({ status: g.status, count: g._count._all })),
    budget: {
      totalPlanned: totalPlanned.toFixed(2),
      totalSpent: totalSpent.toFixed(2),
      utilization: totalPlanned.gt(0) ? Number(totalSpent.div(totalPlanned).mul(100).toFixed(1)) : 0,
    },
    recentProjects,
    upcomingMilestones,
  };
}
