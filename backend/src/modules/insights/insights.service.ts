import { ExpenseStatus, Prisma } from '@prisma/client';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';

/** Collaboration graph: members and projects as nodes, team membership as edges. */
export async function network(user: AuthUser) {
  const [users, projects] = await Promise.all([
    prisma.user.findMany({ where: { orgId: user.orgId }, select: { id: true, name: true } }),
    prisma.project.findMany({
      where: { orgId: user.orgId },
      select: { id: true, title: true, status: true, team: { select: { userId: true } } },
    }),
  ]);

  const nodes = [
    ...users.map((u) => ({ id: `u:${u.id}`, label: u.name, type: 'member' as const })),
    ...projects.map((p) => ({ id: `p:${p.id}`, label: p.title, type: 'project' as const, status: p.status })),
  ];
  const links = projects.flatMap((p) => p.team.map((t) => ({ source: `u:${t.userId}`, target: `p:${p.id}` })));

  return { nodes, links };
}

/** Cumulative approved spend over time + total planned, for burn-rate forecasting. */
export async function burnRate(user: AuthUser) {
  const expenses = await prisma.expense.findMany({
    where: { status: ExpenseStatus.APPROVED, budgetItem: { project: { orgId: user.orgId } } },
    select: { amount: true, date: true },
    orderBy: { date: 'asc' },
  });

  let cumulative = 0;
  const points = expenses.map((e) => {
    cumulative += Number(e.amount);
    return { date: e.date.toISOString().slice(0, 10), cumulative };
  });

  const plannedAgg = await prisma.budgetItem.aggregate({
    where: { project: { orgId: user.orgId } },
    _sum: { plannedAmount: true },
  });
  const firstProject = await prisma.project.findFirst({
    where: { orgId: user.orgId },
    select: { currency: true },
    orderBy: { createdAt: 'asc' },
  });

  return {
    points,
    totalPlanned: Number(plannedAgg._sum.plannedAmount ?? new Prisma.Decimal(0)),
    currency: firstProject?.currency ?? 'USD',
  };
}

/** Research-impact metrics: publications over time and citation totals. */
export async function impact(user: AuthUser) {
  const pubs = await prisma.publication.findMany({
    where: { project: { orgId: user.orgId } },
    select: { title: true, journal: true, pubDate: true, citationCount: true, project: { select: { title: true } } },
    orderBy: { pubDate: 'desc' },
  });

  const byYearMap = new Map<string, number>();
  let citations = 0;
  for (const p of pubs) {
    citations += p.citationCount;
    const year = p.pubDate ? String(p.pubDate.getFullYear()) : 'Unknown';
    byYearMap.set(year, (byYearMap.get(year) ?? 0) + 1);
  }

  const byYear = [...byYearMap.entries()]
    .filter(([y]) => y !== 'Unknown')
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([year, count]) => ({ year, count }));

  return {
    totals: { publications: pubs.length, citations },
    byYear,
    recent: pubs.slice(0, 8).map((p) => ({
      title: p.title,
      journal: p.journal,
      citations: p.citationCount,
      project: p.project.title,
    })),
  };
}
