import { ExpenseStatus, Prisma } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';

const sumApproved = (expenses: { amount: Prisma.Decimal; status: ExpenseStatus }[]) =>
  expenses
    .filter((e) => e.status === ExpenseStatus.APPROVED)
    .reduce((acc, e) => acc.add(e.amount), new Prisma.Decimal(0));

/** Compact, grounded snapshot of a whole workspace — fed to the AI for "ask your portfolio". */
export async function buildWorkspaceSnapshot(orgId: string) {
  const org = await prisma.organization.findUnique({ where: { id: orgId }, select: { name: true } });
  const projects = await prisma.project.findMany({
    where: { orgId },
    select: {
      title: true,
      status: true,
      currency: true,
      _count: { select: { team: true, publications: true } },
      milestones: { select: { status: true } },
      budgetItems: { select: { plannedAmount: true, expenses: { select: { amount: true, status: true } } } },
    },
  });

  let totalPlanned = new Prisma.Decimal(0);
  let totalSpent = new Prisma.Decimal(0);

  const projectRows = projects.map((p) => {
    const planned = p.budgetItems.reduce((acc, b) => acc.add(b.plannedAmount), new Prisma.Decimal(0));
    const spent = p.budgetItems.reduce((acc, b) => acc.add(sumApproved(b.expenses)), new Prisma.Decimal(0));
    totalPlanned = totalPlanned.add(planned);
    totalSpent = totalSpent.add(spent);
    return {
      title: p.title,
      status: p.status,
      currency: p.currency,
      planned: Number(planned),
      spent: Number(spent),
      utilizationPct: planned.gt(0) ? Math.round(Number(spent.div(planned)) * 100) : 0,
      team: p._count.team,
      publications: p._count.publications,
      milestonesDone: p.milestones.filter((m) => m.status === 'DONE').length,
      milestonesOpen: p.milestones.filter((m) => m.status !== 'DONE').length,
    };
  });

  const ideas = await prisma.idea.findMany({
    where: { user: { orgId } },
    select: { title: true, priority: true, status: true },
    orderBy: { priority: 'desc' },
    take: 30,
  });

  return {
    workspace: org?.name ?? 'Workspace',
    projectCount: projects.length,
    totals: { planned: Number(totalPlanned), spent: Number(totalSpent) },
    projects: projectRows,
    ideas,
  };
}

/** Detailed snapshot of one project — fed to the AI report writer. */
export async function buildProjectSnapshot(orgId: string, projectId: string) {
  const project = await prisma.project.findFirst({
    where: { id: projectId, orgId },
    include: {
      lead: { select: { name: true } },
      team: { include: { user: { select: { name: true } } } },
      milestones: { orderBy: { dueDate: 'asc' } },
      publications: true,
      budgetItems: { include: { expenses: { select: { amount: true, status: true } } } },
    },
  });
  if (!project) throw new NotFoundError('Project not found');

  const budget = project.budgetItems.map((b) => ({
    category: b.category,
    planned: Number(b.plannedAmount),
    spent: Number(sumApproved(b.expenses)),
  }));

  return {
    title: project.title,
    summary: project.summary,
    status: project.status,
    currency: project.currency,
    startDate: project.startDate,
    endDate: project.endDate,
    lead: project.lead?.name ?? null,
    team: project.team.map((t) => ({ name: t.user.name, role: t.role })),
    milestones: project.milestones.map((m) => ({ description: m.description, status: m.status, dueDate: m.dueDate })),
    publications: project.publications.map((p) => ({ title: p.title, journal: p.journal, doi: p.doi })),
    budget,
    budgetTotals: {
      planned: budget.reduce((s, b) => s + b.planned, 0),
      spent: budget.reduce((s, b) => s + b.spent, 0),
    },
  };
}
