import { ExpenseStatus, Prisma } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateBudgetItemInput, CreateExpenseInput, UpdateBudgetItemInput } from './budget.schema.js';

/** Ensures the project belongs to the caller's org before touching its budget. */
async function assertOwnedProject(projectId: string, orgId: string) {
  const project = await prisma.project.findFirst({ where: { id: projectId, orgId } });
  if (!project) throw new NotFoundError('Project not found');
  return project;
}

/** Org-wide portfolio view: planned vs. approved-spent per project. */
export async function orgOverview(user: AuthUser) {
  const projects = await prisma.project.findMany({
    where: { orgId: user.orgId },
    orderBy: { updatedAt: 'desc' },
    select: {
      id: true,
      title: true,
      status: true,
      currency: true,
      budgetItems: {
        select: { plannedAmount: true, expenses: { select: { amount: true, status: true } } },
      },
    },
  });

  const rows = projects.map((p) => {
    let planned = new Prisma.Decimal(0);
    let spent = new Prisma.Decimal(0);
    for (const item of p.budgetItems) {
      planned = planned.add(item.plannedAmount);
      for (const e of item.expenses) {
        if (e.status === ExpenseStatus.APPROVED) spent = spent.add(e.amount);
      }
    }
    return {
      id: p.id,
      title: p.title,
      status: p.status,
      currency: p.currency,
      lines: p.budgetItems.length,
      planned: planned.toFixed(2),
      spent: spent.toFixed(2),
      remaining: planned.sub(spent).toFixed(2),
      utilization: planned.gt(0) ? Number(spent.div(planned).mul(100).toFixed(1)) : 0,
    };
  });

  const totalPlanned = rows.reduce((s, r) => s + Number(r.planned), 0);
  const totalSpent = rows.reduce((s, r) => s + Number(r.spent), 0);

  return { rows, totals: { planned: totalPlanned.toFixed(2), spent: totalSpent.toFixed(2) } };
}

/** Ensures the budget item exists and rolls up through a project in the caller's org. */
async function assertOwnedBudgetItem(budgetItemId: string, orgId: string) {
  const item = await prisma.budgetItem.findFirst({
    where: { id: budgetItemId, project: { orgId } },
  });
  if (!item) throw new NotFoundError('Budget item not found');
  return item;
}

export async function listBudget(user: AuthUser, projectId: string) {
  await assertOwnedProject(projectId, user.orgId);

  const items = await prisma.budgetItem.findMany({
    where: { projectId },
    orderBy: { category: 'asc' },
    include: {
      expenses: { orderBy: { date: 'desc' }, include: { user: { select: { id: true, name: true } } } },
    },
  });

  // Planned vs. actual rollup. Only APPROVED expenses count against "spent".
  const summary = items.map((item) => {
    const spent = item.expenses
      .filter((e) => e.status === ExpenseStatus.APPROVED)
      .reduce((acc, e) => acc.add(e.amount), new Prisma.Decimal(0));
    const pending = item.expenses
      .filter((e) => e.status === ExpenseStatus.PENDING)
      .reduce((acc, e) => acc.add(e.amount), new Prisma.Decimal(0));
    return {
      ...item,
      spent: spent.toFixed(2),
      pending: pending.toFixed(2),
      remaining: new Prisma.Decimal(item.plannedAmount).sub(spent).toFixed(2),
    };
  });

  const totalPlanned = items.reduce((acc, i) => acc.add(i.plannedAmount), new Prisma.Decimal(0));
  return { items: summary, totalPlanned: totalPlanned.toFixed(2) };
}

export async function createBudgetItem(user: AuthUser, projectId: string, input: CreateBudgetItemInput) {
  await assertOwnedProject(projectId, user.orgId);
  return prisma.budgetItem.create({ data: { ...input, projectId } });
}

export async function updateBudgetItem(user: AuthUser, budgetItemId: string, input: UpdateBudgetItemInput) {
  await assertOwnedBudgetItem(budgetItemId, user.orgId);
  return prisma.budgetItem.update({ where: { id: budgetItemId }, data: input });
}

export async function deleteBudgetItem(user: AuthUser, budgetItemId: string) {
  await assertOwnedBudgetItem(budgetItemId, user.orgId);
  await prisma.budgetItem.delete({ where: { id: budgetItemId } });
}

export async function submitExpense(user: AuthUser, budgetItemId: string, input: CreateExpenseInput) {
  await assertOwnedBudgetItem(budgetItemId, user.orgId);
  return prisma.expense.create({
    data: {
      budgetItemId,
      userId: user.id,
      amount: input.amount,
      currency: input.currency,
      date: input.date,
      description: input.description,
      receiptUrl: input.receiptUrl,
      status: ExpenseStatus.PENDING,
    },
  });
}

/** Approve or reject a pending expense. Reserved for finance/admin roles at the router. */
export async function decideExpense(user: AuthUser, expenseId: string, decision: 'APPROVED' | 'REJECTED') {
  const expense = await prisma.expense.findFirst({
    where: { id: expenseId, budgetItem: { project: { orgId: user.orgId } } },
  });
  if (!expense) throw new NotFoundError('Expense not found');

  return prisma.expense.update({
    where: { id: expenseId },
    data: { status: ExpenseStatus[decision] },
  });
}
