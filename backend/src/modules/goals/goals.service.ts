import { Prisma } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import type { CreateContributionInput, CreateGoalInput, UpdateGoalInput } from './goals.schema.js';

async function assertOwnedGoal(id: string, userId: string) {
  const goal = await prisma.savingsGoal.findFirst({ where: { id, userId } });
  if (!goal) throw new NotFoundError('Goal not found');
  return goal;
}

const MS_PER_MONTH = 30.44 * 24 * 60 * 60 * 1000;

type PlanRow = {
  id: string;
  name: string;
  amount: Prisma.Decimal;
  frequency: 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
  interval: number;
  nextRun: Date;
};

/** Normalize a recurring plan's amount to an equivalent monthly figure. */
function monthlyEquivalent(plan: PlanRow): number {
  const amt = Number(plan.amount);
  const per = Math.max(1, plan.interval);
  switch (plan.frequency) {
    case 'DAILY':
      return (amt * 30.44) / per;
    case 'WEEKLY':
      return (amt * (30.44 / 7)) / per;
    case 'MONTHLY':
      return amt / per;
    case 'YEARLY':
      return amt / (12 * per);
  }
}

function serializeGoal(goal: {
  targetAmount: Prisma.Decimal;
  deadline: Date | null;
  achievedAt?: Date | null;
  contributions: { amount: Prisma.Decimal }[];
  recurringRules?: PlanRow[];
} & Record<string, unknown>) {
  const zero = new Prisma.Decimal(0);
  const saved = goal.contributions.reduce((s, c) => s.add(c.amount), zero);
  const pct = goal.targetAmount.gt(0) ? Number(saved.div(goal.targetAmount).mul(100).toFixed(1)) : 0;
  const remaining = goal.targetAmount.sub(saved);

  // How much per month is needed to reach the target by the deadline.
  let monthlyNeeded: string | null = null;
  if (goal.deadline && saved.lt(goal.targetAmount)) {
    const monthsLeft = Math.max(1, (goal.deadline.getTime() - Date.now()) / MS_PER_MONTH);
    monthlyNeeded = remaining.div(monthsLeft).toFixed(2);
  }

  // Auto-save: what recurring plans feed this goal, and when they'll finish it.
  const plans = goal.recurringRules ?? [];
  const monthlyAutoSave = plans.reduce((s, p) => s + monthlyEquivalent(p), 0);
  const nextRun = plans.length
    ? plans.reduce<Date | null>((min, p) => (!min || p.nextRun < min ? p.nextRun : min), null)
    : null;

  let projectedDate: string | null = null;
  let onTrack: boolean | null = null;
  if (!goal.achievedAt && remaining.gt(0) && monthlyAutoSave > 0) {
    const monthsToFinish = Number(remaining) / monthlyAutoSave;
    const projected = new Date(Date.now() + monthsToFinish * MS_PER_MONTH);
    projectedDate = projected.toISOString();
    if (goal.deadline) onTrack = projected <= goal.deadline;
  }

  const { recurringRules, ...rest } = goal;
  void recurringRules;

  return {
    ...rest,
    targetAmount: goal.targetAmount.toFixed(2),
    saved: saved.toFixed(2),
    remaining: Prisma.Decimal.max(zero, remaining).toFixed(2),
    pct: Math.min(100, pct),
    monthlyNeeded,
    autoSave: {
      monthly: monthlyAutoSave.toFixed(2),
      planCount: plans.length,
      nextRun: nextRun ? nextRun.toISOString() : null,
      projectedDate,
      onTrack,
    },
    contributions: goal.contributions.map((c) => ({ ...c, amount: c.amount.toFixed(2) })),
  };
}

const goalInclude = {
  contributions: { orderBy: { date: 'desc' as const } },
  recurringRules: {
    where: { active: true },
    select: { id: true, name: true, amount: true, frequency: true, interval: true, nextRun: true },
  },
};

export async function list(user: AuthUser) {
  const goals = await prisma.savingsGoal.findMany({
    where: { userId: user.id },
    orderBy: [{ achievedAt: 'asc' }, { createdAt: 'desc' }],
    include: goalInclude,
  });
  return { items: goals.map(serializeGoal) };
}

export async function create(user: AuthUser, input: CreateGoalInput) {
  const goal = await prisma.savingsGoal.create({
    data: { ...input, userId: user.id },
    include: goalInclude,
  });
  return serializeGoal(goal);
}

export async function update(user: AuthUser, id: string, input: UpdateGoalInput) {
  await assertOwnedGoal(id, user.id);
  const goal = await prisma.savingsGoal.update({ where: { id }, data: input, include: goalInclude });
  return serializeGoal(goal);
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedGoal(id, user.id);
  await prisma.savingsGoal.delete({ where: { id } });
}

export async function addContribution(user: AuthUser, goalId: string, input: CreateContributionInput) {
  const goal = await assertOwnedGoal(goalId, user.id);

  await prisma.goalContribution.create({ data: { goalId, ...input } });

  // Mark achieved (once) when contributions reach the target.
  if (!goal.achievedAt) {
    const sum = await prisma.goalContribution.aggregate({ where: { goalId }, _sum: { amount: true } });
    const saved = sum._sum.amount ?? new Prisma.Decimal(0);
    if (saved.gte(goal.targetAmount)) {
      await prisma.savingsGoal.update({ where: { id: goalId }, data: { achievedAt: new Date() } });
      await notify(user.id, 'goal_achieved', `🎉 You reached your "${goal.name}" goal!`, '/goals');
    }
  }

  const updated = await prisma.savingsGoal.findUniqueOrThrow({ where: { id: goalId }, include: goalInclude });
  return serializeGoal(updated);
}

export async function removeContribution(user: AuthUser, goalId: string, contributionId: string) {
  await assertOwnedGoal(goalId, user.id);
  const contribution = await prisma.goalContribution.findFirst({
    where: { id: contributionId, goalId },
  });
  if (!contribution) throw new NotFoundError('Contribution not found');
  await prisma.goalContribution.delete({ where: { id: contributionId } });
}
