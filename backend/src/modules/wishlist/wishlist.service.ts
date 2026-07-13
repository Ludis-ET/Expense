import { Prisma, SpendLockKind, TxKind, WishlistStatus } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import * as goalsService from '../goals/goals.service.js';
import * as transactions from '../transactions/transactions.service.js';
import { spendableFor } from '../spend-locks/spend-locks.service.js';
import type {
  CreateWishlistInput,
  FundWishlistInput,
  ListWishlistQuery,
  PromoteWishlistInput,
  PurchaseWishlistInput,
  UpdateWishlistInput,
} from './wishlist.schema.js';

type ItemRow = {
  id: string;
  name: string;
  estimatedCost: Prisma.Decimal;
  currency: string;
  priority: number;
  status: WishlistStatus;
  note: string | null;
  link: string | null;
  emoji: string | null;
  savedAmount: Prisma.Decimal;
  goalId: string | null;
  goal?: { id: string; name: string } | null;
  createdAt: Date;
  updatedAt: Date;
};

/** `spendable` = unlocked money available in the item's currency (or null when unknown). */
function serialize(item: ItemRow, spendable?: number | null) {
  const cost = Number(item.estimatedCost);
  const saved = Number(item.savedAmount);
  const remaining = Math.max(0, cost - saved);
  const pct = cost > 0 ? Math.min(100, Math.round((saved / cost) * 100)) : 0;
  const isActive = item.status === WishlistStatus.WANTING || item.status === WishlistStatus.SAVING;
  return {
    id: item.id,
    name: item.name,
    estimatedCost: item.estimatedCost.toFixed(2),
    currency: item.currency,
    priority: item.priority,
    status: item.status,
    note: item.note,
    link: item.link,
    emoji: item.emoji,
    savedAmount: item.savedAmount.toFixed(2),
    remaining: remaining.toFixed(2),
    pct,
    // Can you cover what's left out of unlocked money right now?
    affordable: spendable == null || !isActive ? null : spendable + 0.001 >= remaining,
    goalId: item.goalId,
    goal: item.goal ? { id: item.goal.id, name: item.goal.name } : null,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
  };
}

const include = { goal: { select: { id: true, name: true } } } satisfies Prisma.WishlistItemInclude;

async function assertOwned(id: string, userId: string) {
  const item = await prisma.wishlistItem.findFirst({ where: { id, userId }, include });
  if (!item) throw new NotFoundError('Wishlist item not found');
  return item as ItemRow;
}

/** Spendable-per-currency map for the currencies present in a set of items. */
async function spendableByCurrency(userId: string, currencies: string[]) {
  const uniq = [...new Set(currencies)];
  const rows = await Promise.all(uniq.map(async (c) => [c, Number((await spendableFor(userId, c)).spendable)] as const));
  return new Map(rows);
}

export async function list(user: AuthUser, query: ListWishlistQuery) {
  const items = (await prisma.wishlistItem.findMany({
    where: {
      userId: user.id,
      ...(query.currency ? { currency: query.currency.toUpperCase() } : {}),
      ...(query.status ? { status: query.status } : {}),
    },
    include,
    orderBy: [{ priority: 'asc' }, { createdAt: 'desc' }],
  })) as ItemRow[];

  const spendable = await spendableByCurrency(user.id, items.map((i) => i.currency));

  const active = items.filter((i) => i.status === WishlistStatus.WANTING || i.status === WishlistStatus.SAVING);
  const dreamTotal = active.reduce((s, i) => s + Number(i.estimatedCost), 0);
  const savedTotal = active.reduce((s, i) => s + Number(i.savedAmount), 0);
  const serialized = items.map((i) => serialize(i, spendable.get(i.currency)));

  return {
    items: serialized,
    stats: {
      wanting: items.filter((i) => i.status === WishlistStatus.WANTING).length,
      saving: items.filter((i) => i.status === WishlistStatus.SAVING).length,
      bought: items.filter((i) => i.status === WishlistStatus.BOUGHT).length,
      affordable: serialized.filter((i) => i.affordable).length,
      dreamTotal: dreamTotal.toFixed(2),
      savedTotal: savedTotal.toFixed(2),
      currency: query.currency?.toUpperCase() ?? null,
    },
  };
}

/** Compact wishlist digest for the dashboard: closest-to-owning active wants. */
export async function dashboard(user: AuthUser, currency: string) {
  const cur = currency.toUpperCase();
  const items = (await prisma.wishlistItem.findMany({
    where: { userId: user.id, currency: cur, status: { in: [WishlistStatus.WANTING, WishlistStatus.SAVING] } },
    include,
    orderBy: [{ priority: 'asc' }, { createdAt: 'desc' }],
  })) as ItemRow[];
  const spendable = Number((await spendableFor(user.id, cur)).spendable);
  const serialized = items.map((i) => serialize(i, spendable));

  return {
    currency: cur,
    activeCount: serialized.length,
    affordableCount: serialized.filter((i) => i.affordable).length,
    dreamTotal: items.reduce((s, i) => s + Number(i.estimatedCost), 0).toFixed(2),
    top: serialized
      .slice()
      .sort((a, b) => (b.affordable === a.affordable ? b.pct - a.pct : a.affordable ? -1 : 1))
      .slice(0, 3),
  };
}

export async function create(user: AuthUser, input: CreateWishlistInput) {
  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const item = (await prisma.wishlistItem.create({
    data: {
      userId: user.id,
      name: input.name.trim(),
      estimatedCost: input.estimatedCost,
      currency: input.currency.toUpperCase(),
      priority: input.priority,
      note: input.note,
      link: input.link || null,
      emoji: input.emoji,
      goalId: input.goalId,
      status: input.status ?? WishlistStatus.WANTING,
      savedAmount: input.savedAmount ?? 0,
    },
    include,
  })) as ItemRow;

  return serialize(item, Number((await spendableFor(user.id, item.currency)).spendable));
}

export async function update(user: AuthUser, id: string, input: UpdateWishlistInput) {
  await assertOwned(id, user.id);

  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.estimatedCost !== undefined ? { estimatedCost: input.estimatedCost } : {}),
      ...(input.currency !== undefined ? { currency: input.currency.toUpperCase() } : {}),
      ...(input.priority !== undefined ? { priority: input.priority } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.link !== undefined ? { link: input.link || null } : {}),
      ...(input.emoji !== undefined ? { emoji: input.emoji } : {}),
      ...(input.goalId !== undefined ? { goalId: input.goalId } : {}),
      ...(input.status !== undefined ? { status: input.status } : {}),
      ...(input.savedAmount !== undefined ? { savedAmount: input.savedAmount } : {}),
    },
    include,
  })) as ItemRow;

  return serialize(item, Number((await spendableFor(user.id, item.currency)).spendable));
}

/**
 * Set aside money toward a want. Bumps its own progress and, when the want is
 * linked to a savings goal, records a matching goal contribution so both stay
 * in step. Notifies once the want is fully funded.
 */
export async function fund(user: AuthUser, id: string, input: FundWishlistInput) {
  const existing = await assertOwned(id, user.id);
  if (existing.status === WishlistStatus.BOUGHT || existing.status === WishlistStatus.DROPPED) {
    throw new BadRequestError('This want is already closed');
  }

  const cost = existing.estimatedCost;
  const nextSaved = Prisma.Decimal.min(cost, existing.savedAmount.add(input.amount));
  const wasFunded = existing.savedAmount.gte(cost);

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: {
      savedAmount: nextSaved,
      status: existing.status === WishlistStatus.WANTING ? WishlistStatus.SAVING : existing.status,
    },
    include,
  })) as ItemRow;

  if (existing.goalId) {
    await goalsService.addContribution(user, existing.goalId, {
      amount: input.amount,
      note: `Toward "${existing.name}"`,
    } as never);
  }

  if (!wasFunded && nextSaved.gte(cost)) {
    await notify(user.id, 'wishlist_funded', `🎯 You've fully funded "${existing.name}" — ready to buy!`, '/wishlist');
  }

  return serialize(item, Number((await spendableFor(user.id, item.currency)).spendable));
}

/**
 * Turn a want into a first-class savings goal: creates the goal, links the want,
 * seeds a contribution for whatever is already saved, and optionally opens a
 * GOAL spend-lock so the reserved money is protected.
 */
export async function promoteToGoal(user: AuthUser, id: string, input: PromoteWishlistInput) {
  const existing = await assertOwned(id, user.id);
  if (existing.goalId) throw new BadRequestError('This want is already linked to a goal');

  const goal = (await goalsService.create(user, {
    name: existing.name,
    targetAmount: Number(existing.estimatedCost),
    icon: null,
    color: null,
    note: existing.note ?? null,
    deadline: input.deadline ?? null,
  } as never)) as unknown as { id: string };

  if (Number(existing.savedAmount) > 0) {
    await goalsService.addContribution(user, goal.id, {
      amount: Number(existing.savedAmount),
      note: 'Carried over from wishlist',
    } as never);
  }

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: { goalId: goal.id, status: WishlistStatus.SAVING },
    include,
  })) as ItemRow;

  let lockId: string | null = null;
  if (input.createLock) {
    const lock = await prisma.spendLock.create({
      data: {
        userId: user.id,
        kind: SpendLockKind.GOAL,
        name: existing.name,
        amount: existing.estimatedCost,
        currency: existing.currency,
        goalId: goal.id,
        note: 'Reserve for wishlist goal',
      },
    });
    lockId = lock.id;
  }

  await notify(user.id, 'wishlist_promoted', `⭐ "${existing.name}" is now a savings goal.`, '/budgets?tab=goals');

  return {
    item: serialize(item, Number((await spendableFor(user.id, item.currency)).spendable)),
    goalId: goal.id,
    lockId,
  };
}

/**
 * Buy the want: writes a real EXPENSE against the chosen account/category and
 * marks the item BOUGHT. If it was reserved behind a GOAL lock, that lock is
 * released first so the planned purchase isn't blocked by its own reserve.
 */
export async function purchase(user: AuthUser, id: string, input: PurchaseWishlistInput) {
  const existing = await assertOwned(id, user.id);
  if (existing.status === WishlistStatus.BOUGHT) throw new BadRequestError('Already marked bought');

  const amount = input.amount ?? Number(existing.estimatedCost);

  if (existing.goalId) {
    const { releaseGoalLocks } = await import('../spend-locks/spend-locks.service.js');
    await releaseGoalLocks(user.id, existing.goalId);
  }

  const tx = await transactions.create(user, {
    kind: TxKind.EXPENSE,
    amount,
    currency: existing.currency,
    date: input.date ?? new Date(),
    accountId: input.accountId,
    categoryId: input.categoryId,
    payee: existing.name,
    note: input.note ?? `Wishlist purchase`,
    tags: ['wishlist'],
  } as never);

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: { status: WishlistStatus.BOUGHT },
    include,
  })) as ItemRow;

  await notify(user.id, 'wishlist_bought', `🛍️ You bought "${existing.name}". Enjoy it!`, '/transactions');

  return { item: serialize(item, null), transaction: tx };
}

export async function remove(user: AuthUser, id: string) {
  await assertOwned(id, user.id);
  await prisma.wishlistItem.delete({ where: { id } });
}
