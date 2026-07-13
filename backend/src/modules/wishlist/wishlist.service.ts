import { Prisma, WishlistStatus } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateWishlistInput, ListWishlistQuery, UpdateWishlistInput } from './wishlist.schema.js';

function serialize(item: {
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
}) {
  const cost = Number(item.estimatedCost);
  const saved = Number(item.savedAmount);
  const pct = cost > 0 ? Math.min(100, Math.round((saved / cost) * 100)) : 0;
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
    remaining: Math.max(0, cost - saved).toFixed(2),
    pct,
    goalId: item.goalId,
    goal: item.goal ? { id: item.goal.id, name: item.goal.name } : null,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
  };
}

const include = { goal: { select: { id: true, name: true } } } satisfies Prisma.WishlistItemInclude;

export async function list(user: AuthUser, query: ListWishlistQuery) {
  const items = await prisma.wishlistItem.findMany({
    where: {
      userId: user.id,
      ...(query.currency ? { currency: query.currency.toUpperCase() } : {}),
      ...(query.status ? { status: query.status } : {}),
    },
    include,
    orderBy: [{ priority: 'asc' }, { createdAt: 'desc' }],
  });

  const active = items.filter((i) => i.status === WishlistStatus.WANTING || i.status === WishlistStatus.SAVING);
  const dreamTotal = active.reduce((s, i) => s + Number(i.estimatedCost), 0);
  const savedTotal = active.reduce((s, i) => s + Number(i.savedAmount), 0);

  return {
    items: items.map(serialize),
    stats: {
      wanting: items.filter((i) => i.status === WishlistStatus.WANTING).length,
      saving: items.filter((i) => i.status === WishlistStatus.SAVING).length,
      bought: items.filter((i) => i.status === WishlistStatus.BOUGHT).length,
      dreamTotal: dreamTotal.toFixed(2),
      savedTotal: savedTotal.toFixed(2),
      currency: query.currency?.toUpperCase() ?? null,
    },
  };
}

export async function create(user: AuthUser, input: CreateWishlistInput) {
  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const item = await prisma.wishlistItem.create({
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
  });

  return serialize(item);
}

export async function update(user: AuthUser, id: string, input: UpdateWishlistInput) {
  const existing = await prisma.wishlistItem.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Wishlist item not found');

  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const item = await prisma.wishlistItem.update({
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
  });

  return serialize(item);
}

export async function remove(user: AuthUser, id: string) {
  const existing = await prisma.wishlistItem.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Wishlist item not found');
  await prisma.wishlistItem.delete({ where: { id } });
}
