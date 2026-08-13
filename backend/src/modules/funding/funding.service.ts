/**
 * Payday rules.
 *
 * "When my salary lands, fill Rent, then Groceries, then Transport." Every piece
 * of this already existed - recurring rules, plans, allocations - and none of it
 * was joined up, so filling plans meant doing it by hand every month. A plan
 * nobody refills is just a number going stale, which is why this is the feature
 * that makes envelopes worth keeping.
 *
 * Nothing here moves money on its own unless the user has said it may. A rule is
 * `confirmFirst` by default: the income lands, Santim works out the plan and
 * offers it, and the user taps once. Money moving unannounced is alarming the
 * first time it happens.
 */
import { FundingStepMode, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { fundPlan, fundedThisCycle, loadSnapshot, ZERO } from '../../core/money/index.js';
import { notify } from '../notifications/notifications.service.js';
import type { CreateFundingRuleInput, UpdateFundingRuleInput } from './funding.schema.js';

const ruleInclude = {
  account: { select: { id: true, name: true, type: true, currency: true } },
  steps: {
    orderBy: { position: 'asc' as const },
    include: {
      budget: {
        select: { id: true, name: true, icon: true, color: true, currency: true, plannedAmount: true },
      },
    },
  },
} satisfies Prisma.FundingRuleInclude;

type RuleRow = Prisma.FundingRuleGetPayload<{ include: typeof ruleInclude }>;

function serialize(rule: RuleRow) {
  return {
    id: rule.id,
    name: rule.name,
    accountId: rule.accountId,
    account: rule.account,
    currency: rule.currency,
    minAmount: rule.minAmount.toFixed(2),
    active: rule.active,
    confirmFirst: rule.confirmFirst,
    lastRunAt: rule.lastRunAt ? rule.lastRunAt.toISOString() : null,
    steps: rule.steps.map((s) => ({
      id: s.id,
      budgetId: s.budgetId,
      budget: s.budget ? { ...s.budget, plannedAmount: s.budget.plannedAmount.toFixed(2) } : null,
      position: s.position,
      mode: s.mode,
      amount: s.amount.toFixed(2),
    })),
    createdAt: rule.createdAt.toISOString(),
  };
}

export type SerializedFundingRule = ReturnType<typeof serialize>;

async function assertOwned(id: string, userId: string) {
  const rule = await prisma.fundingRule.findFirst({ where: { id, userId }, include: ruleInclude });
  if (!rule) throw new NotFoundError('Payday rule not found');
  return rule;
}

export async function list(user: AuthUser) {
  const rules = await prisma.fundingRule.findMany({
    where: { userId: user.id },
    orderBy: [{ active: 'desc' }, { createdAt: 'desc' }],
    include: ruleInclude,
  });
  return { items: rules.map(serialize) };
}

export async function getById(user: AuthUser, id: string) {
  return serialize(await assertOwned(id, user.id));
}

async function assertRefs(userId: string, input: { accountId?: string | null; steps?: Array<{ budgetId: string }> }) {
  if (input.accountId) {
    const account = await prisma.account.findFirst({ where: { id: input.accountId, userId } });
    if (!account) throw new NotFoundError('Account not found');
  }
  if (input.steps?.length) {
    const ids = input.steps.map((s) => s.budgetId);
    const found = await prisma.budget.count({ where: { id: { in: ids }, userId } });
    if (found !== new Set(ids).size) throw new NotFoundError('One of those plans does not exist');
  }
}

export async function create(user: AuthUser, input: CreateFundingRuleInput) {
  await assertRefs(user.id, input);

  const rule = await prisma.fundingRule.create({
    data: {
      userId: user.id,
      name: input.name.trim(),
      accountId: input.accountId ?? null,
      currency: input.currency.toUpperCase(),
      minAmount: input.minAmount,
      active: input.active,
      confirmFirst: input.confirmFirst,
      steps: {
        create: input.steps.map((s, index) => ({
          budgetId: s.budgetId,
          position: index,
          mode: s.mode,
          amount: s.amount ?? 0,
        })),
      },
    },
    include: ruleInclude,
  });
  return serialize(rule);
}

export async function update(user: AuthUser, id: string, input: UpdateFundingRuleInput) {
  await assertOwned(id, user.id);
  await assertRefs(user.id, input);

  const rule = await prisma.$transaction(async (tx) => {
    if (input.steps) {
      // Order carries meaning here - which plan gets filled first when the money
      // runs out partway down - so the list is replaced wholesale rather than
      // patched row by row.
      await tx.fundingStep.deleteMany({ where: { fundingRuleId: id } });
      await tx.fundingStep.createMany({
        data: input.steps.map((s, index) => ({
          fundingRuleId: id,
          budgetId: s.budgetId,
          position: index,
          mode: s.mode,
          amount: s.amount ?? 0,
        })),
      });
    }
    return tx.fundingRule.update({
      where: { id },
      data: {
        ...(input.name !== undefined ? { name: input.name.trim() } : {}),
        ...(input.accountId !== undefined ? { accountId: input.accountId } : {}),
        ...(input.currency !== undefined ? { currency: input.currency.toUpperCase() } : {}),
        ...(input.minAmount !== undefined ? { minAmount: input.minAmount } : {}),
        ...(input.active !== undefined ? { active: input.active } : {}),
        ...(input.confirmFirst !== undefined ? { confirmFirst: input.confirmFirst } : {}),
      },
      include: ruleInclude,
    });
  });

  return serialize(rule);
}

export async function remove(user: AuthUser, id: string) {
  await assertOwned(id, user.id);
  await prisma.fundingRule.delete({ where: { id } });
}

// ---------------------------------------------------------------------------
// Working out the split
// ---------------------------------------------------------------------------

export interface PlannedFill {
  budgetId: string;
  budgetName: string;
  icon: string | null;
  color: string | null;
  amount: string;
  mode: FundingStepMode;
  /** Set when the money ran out before this plan got its full share. */
  short: string | null;
}

export interface FundingPreview {
  ruleId: string;
  ruleName: string;
  accountId: string;
  accountName: string;
  currency: string;
  /** What there is to work with: free money in the wallet. */
  availableAmount: string;
  /** The income that triggered this, when there is one. */
  triggerAmount: string | null;
  fills: PlannedFill[];
  totalAmount: string;
  leftOver: string;
}

/**
 * Work out what a rule would do, without doing it.
 *
 * Steps take their share in order, so the plans that matter are funded even when
 * the money runs out partway down the list. Nothing is ever planned beyond what
 * the wallet actually has free, or beyond what a plan can still hold.
 */
export async function preview(
  user: AuthUser,
  ruleId: string,
  opts: { accountId?: string; basis?: Prisma.Decimal } = {},
): Promise<FundingPreview> {
  const rule = await assertOwned(ruleId, user.id);

  const accountId = opts.accountId ?? rule.accountId;
  if (!accountId) {
    throw new BadRequestError('Say which wallet this payday landed in.');
  }
  const account = await prisma.account.findFirst({
    where: { id: accountId, userId: user.id },
    select: { id: true, name: true, currency: true },
  });
  if (!account) throw new NotFoundError('Account not found');

  const snap = await loadSnapshot(user.id);
  const free = snap.available.get(account.id) ?? ZERO;
  // The share PERCENT steps are measured against: the payday when there is one,
  // otherwise whatever the wallet has free right now.
  const basis = opts.basis ?? free;

  let remaining = free;
  const fills: PlannedFill[] = [];

  for (const step of rule.steps) {
    if (!step.budget) continue;
    if (step.budget.currency !== account.currency) continue;

    const budget = await prisma.budget.findUnique({ where: { id: step.budgetId } });
    if (!budget) continue;
    const funded = await fundedThisCycle(prisma, budget);
    const room = Prisma.Decimal.max(ZERO, budget.plannedAmount.sub(funded));

    let want: Prisma.Decimal;
    switch (step.mode) {
      case FundingStepMode.FIXED:
        want = step.amount;
        break;
      case FundingStepMode.PERCENT:
        want = basis.mul(step.amount).div(100);
        break;
      default:
        want = room;
    }

    want = Prisma.Decimal.min(want, room);
    const give = Prisma.Decimal.min(want, remaining);
    if (give.lte(0)) {
      if (want.gt(0)) {
        fills.push({
          budgetId: step.budgetId,
          budgetName: step.budget.name,
          icon: step.budget.icon,
          color: step.budget.color,
          amount: '0.00',
          mode: step.mode,
          short: want.toFixed(2),
        });
      }
      continue;
    }

    fills.push({
      budgetId: step.budgetId,
      budgetName: step.budget.name,
      icon: step.budget.icon,
      color: step.budget.color,
      amount: give.toFixed(2),
      mode: step.mode,
      short: want.gt(give) ? want.sub(give).toFixed(2) : null,
    });
    remaining = remaining.sub(give);
  }

  const total = fills.reduce((s, f) => s.add(new Prisma.Decimal(f.amount)), ZERO);
  return {
    ruleId: rule.id,
    ruleName: rule.name,
    accountId: account.id,
    accountName: account.name,
    currency: account.currency,
    availableAmount: free.toFixed(2),
    triggerAmount: opts.basis ? opts.basis.toFixed(2) : null,
    fills,
    totalAmount: total.toFixed(2),
    leftOver: free.sub(total).toFixed(2),
  };
}

/** Run a rule for real. Each fill goes through the posting core like any other. */
export async function run(
  user: AuthUser,
  ruleId: string,
  opts: { accountId?: string; basis?: Prisma.Decimal; clientOpId?: string | null } = {},
) {
  const plan = await preview(user, ruleId, opts);
  const filled: PlannedFill[] = [];

  for (const fill of plan.fills) {
    if (Number(fill.amount) <= 0) continue;
    await fundPlan(user.id, fill.budgetId, {
      accountId: plan.accountId,
      amount: fill.amount,
      note: `Payday: ${plan.ruleName}`,
      clientOpId: opts.clientOpId ? `${opts.clientOpId}:${fill.budgetId}` : null,
    });
    filled.push(fill);
  }

  await prisma.fundingRule.update({ where: { id: ruleId }, data: { lastRunAt: new Date() } });

  if (filled.length > 0) {
    await notify(
      user.id,
      'payday_funded',
      `${plan.ruleName} filled ${filled.length} ${filled.length === 1 ? 'plan' : 'plans'} with ${plan.totalAmount} ${plan.currency}.`,
      '/budgets',
    );
  }

  return { ...plan, fills: filled, ran: true };
}

/**
 * Called after income lands. Returns the rule that wants to act on it, so the
 * client can offer it - or runs it outright when the user has said it may.
 */
export async function onIncome(
  userId: string,
  tx: { accountId: string; amount: Prisma.Decimal; currency: string; kind: TxKind },
): Promise<{ suggestion: FundingPreview | null; ran: boolean }> {
  if (tx.kind !== TxKind.INCOME) return { suggestion: null, ran: false };

  const rules = await prisma.fundingRule.findMany({
    where: {
      userId,
      active: true,
      currency: tx.currency.toUpperCase(),
      OR: [{ accountId: null }, { accountId: tx.accountId }],
    },
    orderBy: { createdAt: 'asc' },
    include: ruleInclude,
  });

  for (const rule of rules) {
    if (tx.amount.lt(rule.minAmount)) continue;

    const user = { id: userId } as AuthUser;
    const plan = await preview(user, rule.id, { accountId: tx.accountId, basis: tx.amount });
    if (Number(plan.totalAmount) <= 0) continue;

    if (rule.confirmFirst) {
      await notify(
        userId,
        'payday_ready',
        `${plan.totalAmount} ${plan.currency} landed in ${plan.accountName}. "${rule.name}" is ready to fill ${plan.fills.length} ${plan.fills.length === 1 ? 'plan' : 'plans'}.`,
        '/budgets?payday=' + rule.id,
      );
      return { suggestion: plan, ran: false };
    }

    await run(user, rule.id, { accountId: tx.accountId, basis: tx.amount });
    return { suggestion: plan, ran: true };
  }

  return { suggestion: null, ran: false };
}
