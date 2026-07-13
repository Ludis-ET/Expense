import { CategoryKind, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { advanceNextRun, applyOccurrence } from './recurring.engine.js';
import type { CreateRecurringInput, UpdateRecurringInput } from './recurring.schema.js';

const ruleInclude = {
  category: { select: { id: true, name: true, icon: true, color: true } },
  account: { select: { id: true, name: true, type: true } },
  goal: { select: { id: true, name: true, icon: true, color: true } },
  wishlistItem: { select: { id: true, name: true, emoji: true } },
  _count: { select: { transactions: true } },
} as const;

function serialize(
  rule: {
    amount: { toFixed(n: number): string };
    goalId: string | null;
    wishlistItemId: string | null;
    _count: { transactions: number };
  } & Record<string, unknown>,
) {
  const { _count, ...rest } = rule;
  const planType = rule.goalId ? 'goal' : rule.wishlistItemId ? 'wishlist' : 'transaction';
  return { ...rest, amount: rule.amount.toFixed(2), postedCount: _count.transactions, planType };
}

async function assertOwnedRule(id: string, userId: string) {
  const rule = await prisma.recurringRule.findFirst({ where: { id, userId } });
  if (!rule) throw new NotFoundError('Recurring rule not found');
  return rule;
}

async function assertRefsOwned(
  userId: string,
  kind: TxKind,
  input: { accountId?: string; categoryId?: string | null; goalId?: string | null; wishlistItemId?: string | null },
) {
  if (input.accountId) {
    const account = await prisma.account.findFirst({ where: { id: input.accountId, userId } });
    if (!account) throw new NotFoundError('Account not found');
  }
  if (input.categoryId) {
    const category = await prisma.category.findFirst({ where: { id: input.categoryId, userId } });
    if (!category) throw new NotFoundError('Category not found');
    const expected = kind === TxKind.INCOME ? CategoryKind.INCOME : CategoryKind.EXPENSE;
    if (category.kind !== expected) {
      throw new BadRequestError(`"${category.name}" is a ${category.kind.toLowerCase()} category`);
    }
  }
  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId } });
    if (!goal) throw new NotFoundError('Goal not found');
  }
  if (input.wishlistItemId) {
    const item = await prisma.wishlistItem.findFirst({ where: { id: input.wishlistItemId, userId } });
    if (!item) throw new NotFoundError('Wishlist item not found');
  }
}

export async function list(user: AuthUser) {
  const rules = await prisma.recurringRule.findMany({
    where: { userId: user.id },
    orderBy: [{ active: 'desc' }, { nextRun: 'asc' }],
    include: ruleInclude,
  });
  return { items: rules.map(serialize) };
}

export async function create(user: AuthUser, input: CreateRecurringInput) {
  // Savings plans clear the category; goal/wishlist funding doesn't use one.
  const isSavings = !!input.goalId || !!input.wishlistItemId;
  const data = { ...input, categoryId: isSavings ? null : (input.categoryId ?? null) };
  await assertRefsOwned(user.id, input.kind, data);
  const rule = await prisma.recurringRule.create({
    data: { ...data, userId: user.id },
    include: ruleInclude,
  });
  return serialize(rule);
}

export async function update(user: AuthUser, id: string, input: UpdateRecurringInput) {
  const existing = await assertOwnedRule(id, user.id);
  await assertRefsOwned(user.id, (input.kind ?? existing.kind) as TxKind, input);
  const rule = await prisma.recurringRule.update({ where: { id }, data: input, include: ruleInclude });
  return serialize(rule);
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedRule(id, user.id);
  await prisma.recurringRule.delete({ where: { id } });
}

/** Post one occurrence immediately and advance nextRun, regardless of schedule. */
export async function runNow(user: AuthUser, id: string) {
  const rule = await assertOwnedRule(id, user.id);
  if (!rule.active) throw new BadRequestError('This rule is paused - activate it first');

  const now = new Date();
  const applied = await prisma.$transaction(async (dbTx) => {
    const kind = await applyOccurrence(dbTx, user.id, rule, now);
    await dbTx.recurringRule.update({
      where: { id },
      data: { nextRun: advanceNextRun(rule, rule.nextRun > now ? rule.nextRun : now), lastRunAt: now },
    });
    return kind;
  });

  return { applied, name: rule.name, amount: rule.amount.toFixed(2), currency: rule.currency };
}
