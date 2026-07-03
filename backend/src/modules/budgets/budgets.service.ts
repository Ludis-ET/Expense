import { CategoryKind, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { UpsertBudgetInput } from './budgets.schema.js';

export function monthRange(month?: string): { start: Date; end: Date } {
  const now = new Date();
  let y = now.getUTCFullYear();
  let m = now.getUTCMonth() + 1;
  if (month) {
    const parts = month.split('-');
    y = Number(parts[0]);
    m = Number(parts[1]);
  }
  return {
    start: new Date(Date.UTC(y, m - 1, 1)),
    end: new Date(Date.UTC(y, m, 1)),
  };
}

/** Budgets joined with the given month's spend per category. */
export async function list(user: AuthUser, month?: string) {
  const { start, end } = monthRange(month);

  const [budgets, spend] = await Promise.all([
    prisma.budget.findMany({
      where: { userId: user.id },
      include: { category: { select: { id: true, name: true, icon: true, color: true, archived: true } } },
      orderBy: { createdAt: 'asc' },
    }),
    prisma.transaction.groupBy({
      by: ['categoryId'],
      where: { userId: user.id, kind: TxKind.EXPENSE, date: { gte: start, lt: end } },
      _sum: { amount: true },
    }),
  ]);

  const spentByCategory = new Map(spend.map((s) => [s.categoryId, s._sum.amount ?? new Prisma.Decimal(0)]));
  const zero = new Prisma.Decimal(0);

  const items = budgets.map((b) => {
    const spent = spentByCategory.get(b.categoryId) ?? zero;
    const pct = b.amount.gt(0) ? Number(spent.div(b.amount).mul(100).toFixed(1)) : 0;
    const status = pct >= 100 ? 'over' : pct >= b.alertThreshold ? 'warning' : 'ok';
    return {
      id: b.id,
      categoryId: b.categoryId,
      category: b.category,
      amount: b.amount.toFixed(2),
      alertThreshold: b.alertThreshold,
      spent: spent.toFixed(2),
      remaining: b.amount.sub(spent).toFixed(2),
      pct,
      status,
    };
  });

  const totalBudgeted = budgets.reduce((s, b) => s.add(b.amount), zero);
  const totalSpent = items.reduce((s, i) => s.add(new Prisma.Decimal(i.spent)), zero);

  return {
    items,
    totals: {
      budgeted: totalBudgeted.toFixed(2),
      spent: totalSpent.toFixed(2),
      remaining: totalBudgeted.sub(totalSpent).toFixed(2),
    },
  };
}

/** Create or replace the ongoing monthly budget for a category. */
export async function upsert(user: AuthUser, categoryId: string, input: UpsertBudgetInput) {
  const category = await prisma.category.findFirst({ where: { id: categoryId, userId: user.id } });
  if (!category) throw new NotFoundError('Category not found');
  if (category.kind !== CategoryKind.EXPENSE) {
    throw new BadRequestError('Budgets only apply to expense categories');
  }

  return prisma.budget.upsert({
    where: { categoryId },
    create: { userId: user.id, categoryId, ...input },
    update: input,
  });
}

export async function remove(user: AuthUser, categoryId: string) {
  const budget = await prisma.budget.findFirst({ where: { categoryId, userId: user.id } });
  if (!budget) throw new NotFoundError('Budget not found');
  await prisma.budget.delete({ where: { id: budget.id } });
}
