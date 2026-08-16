import { BudgetState, BudgetType, CategoryKind, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { advanceNextRun, applyOccurrence } from './recurring.engine.js';
import type { CreateRecurringInput, UpdateRecurringInput } from './recurring.schema.js';

const ruleInclude = {
  category: { select: { id: true, name: true, icon: true, color: true } },
  account: { select: { id: true, name: true, type: true } },
  budget: { select: { id: true, name: true, icon: true, color: true, currency: true } },
  _count: { select: { transactions: true } },
} as const;

function serialize(
  rule: {
    amount: { toFixed(n: number): string };
    _count: { transactions: number };
  } & Record<string, unknown>,
) {
  const { _count, ...rest } = rule;
  return { ...rest, amount: rule.amount.toFixed(2), postedCount: _count.transactions };
}

async function assertOwnedRule(id: string, userId: string) {
  const rule = await prisma.recurringRule.findFirst({ where: { id, userId } });
  if (!rule) throw new NotFoundError('Recurring rule not found');
  return rule;
}

/**
 * Wallet, category, and (for expenses) the plan this rule draws from.
 *
 * Recurring spends always name an ACTIVE SPENDING plan — one-time or
 * recurring envelopes are both fine. The plan's currency must match the rule
 * (and the paying wallet). Pot shortfall is checked at post time, not here.
 */
async function assertRefsOwned(
  userId: string,
  kind: TxKind,
  input: {
    accountId?: string;
    categoryId?: string | null;
    budgetId?: string | null;
    currency?: string;
  },
) {
  let accountCurrency: string | null = null;
  if (input.accountId) {
    const account = await prisma.account.findFirst({ where: { id: input.accountId, userId } });
    if (!account) throw new NotFoundError('Account not found');
    accountCurrency = account.currency;
    if (input.currency && account.currency !== input.currency) {
      throw new BadRequestError(
        `"${account.name}" holds ${account.currency}; this rule is in ${input.currency}.`,
      );
    }
  }

  if (input.categoryId) {
    const category = await prisma.category.findFirst({ where: { id: input.categoryId, userId } });
    if (!category) throw new NotFoundError('Category not found');
    const expected = kind === TxKind.INCOME ? CategoryKind.INCOME : CategoryKind.EXPENSE;
    if (category.kind !== expected) {
      throw new BadRequestError(`"${category.name}" is a ${category.kind.toLowerCase()} category`);
    }
  }

  if (kind === TxKind.EXPENSE) {
    if (!input.budgetId) {
      throw new BadRequestError('A recurring expense must spend from a plan.');
    }
  } else if (input.budgetId) {
    throw new BadRequestError('Only an expense can be paid out of a plan.');
  }

  if (!input.budgetId) return;

  const budget = await prisma.budget.findFirst({ where: { id: input.budgetId, userId } });
  if (!budget) throw new NotFoundError('Budget plan not found');

  if (budget.state !== BudgetState.ACTIVE) {
    throw new BadRequestError(
      budget.state === BudgetState.CLOSED
        ? `"${budget.name}" is closed - reopen it or pick another plan.`
        : `"${budget.name}" is finished - pick an active spending plan.`,
    );
  }
  if (budget.type !== BudgetType.SPENDING) {
    throw new BadRequestError(
      `"${budget.name}" is a saving plan - recurring spends need a spending envelope.`,
    );
  }
  if (input.currency && budget.currency !== input.currency) {
    throw new BadRequestError(
      `"${budget.name}" is in ${budget.currency}; this rule is in ${input.currency}.`,
    );
  }
  if (accountCurrency && budget.currency !== accountCurrency) {
    throw new BadRequestError(
      `"${budget.name}" is in ${budget.currency}; the paying wallet holds ${accountCurrency}.`,
    );
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
  const data = {
    ...input,
    categoryId: input.categoryId ?? null,
    budgetId: input.kind === TxKind.EXPENSE ? (input.budgetId ?? null) : null,
  };
  await assertRefsOwned(user.id, input.kind, {
    accountId: data.accountId,
    categoryId: data.categoryId,
    budgetId: data.budgetId,
    currency: data.currency,
  });
  const rule = await prisma.recurringRule.create({
    data: { ...data, userId: user.id },
    include: ruleInclude,
  });
  return serialize(rule);
}

export async function update(user: AuthUser, id: string, input: UpdateRecurringInput) {
  const existing = await assertOwnedRule(id, user.id);
  const kind = (input.kind ?? existing.kind) as TxKind;
  const currency = input.currency ?? existing.currency;
  const accountId = input.accountId ?? existing.accountId;
  const categoryId =
    input.categoryId !== undefined ? input.categoryId : existing.categoryId;
  const budgetId =
    kind === TxKind.INCOME
      ? null
      : input.budgetId !== undefined
        ? input.budgetId
        : existing.budgetId;

  await assertRefsOwned(user.id, kind, {
    accountId,
    categoryId,
    budgetId,
    currency,
  });

  const rule = await prisma.recurringRule.update({
    where: { id },
    data: {
      ...input,
      ...(kind === TxKind.INCOME ? { budgetId: null } : {}),
      ...(kind === TxKind.EXPENSE && input.budgetId !== undefined ? { budgetId } : {}),
    },
    include: ruleInclude,
  });
  return serialize(rule);
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedRule(id, user.id);
  await prisma.recurringRule.delete({ where: { id } });
}

/**
 * Post one occurrence immediately and advance nextRun, regardless of schedule.
 *
 * Not wrapped in an outer transaction: the posting core takes its own per-user
 * lock, and holding a transaction across it would deadlock. If the money is not
 * there the occurrence is held and said so, and the clock still moves - a rule
 * that cannot be paid should not jam the schedule behind it.
 */
export async function runNow(user: AuthUser, id: string) {
  const rule = await assertOwnedRule(id, user.id);
  if (!rule.active) throw new BadRequestError('This rule is paused - activate it first');

  const now = new Date();
  const applied = await applyOccurrence(user.id, rule, now);
  await prisma.recurringRule.update({
    where: { id },
    data: { nextRun: advanceNextRun(rule, rule.nextRun > now ? rule.nextRun : now), lastRunAt: now },
  });

  return { applied, name: rule.name, amount: rule.amount.toFixed(2), currency: rule.currency };
}
