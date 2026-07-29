/**
 * The wishlist: things you want, with no money attached.
 *
 * A want is deliberately just an idea - emoji, name, priority, link, note.
 * Acting on one means *planning* it, which spins up a budget plan and links
 * the two; from then on the money lives in the plan, where it belongs.
 */
import { Prisma, WishlistStatus } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import * as budgets from '../budgets/budgets.service.js';
import type {
  CreateWishlistInput,
  ListWishlistQuery,
  PlanWishlistInput,
  UpdateWishlistInput,
} from './wishlist.schema.js';

const planSelect = {
  id: true,
  name: true,
  icon: true,
  color: true,
  currency: true,
  state: true,
  kind: true,
  plannedAmount: true,
} as const;

type ItemRow = {
  id: string;
  name: string;
  priority: number;
  status: WishlistStatus;
  note: string | null;
  link: string | null;
  emoji: string | null;
  budgetId: string | null;
  plannedAt: Date | null;
  boughtAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  budget?: {
    id: string;
    name: string;
    icon: string | null;
    color: string | null;
    currency: string;
    state: string;
    kind: string;
    plannedAmount: Prisma.Decimal;
  } | null;
};

function serialize(item: ItemRow) {
  return {
    id: item.id,
    name: item.name,
    priority: item.priority,
    status: item.status,
    note: item.note,
    link: item.link,
    emoji: item.emoji,
    budgetId: item.budgetId,
    plan: item.budget
      ? {
          id: item.budget.id,
          name: item.budget.name,
          icon: item.budget.icon,
          color: item.budget.color,
          currency: item.budget.currency,
          state: item.budget.state,
          kind: item.budget.kind,
          plannedAmount: item.budget.plannedAmount.toFixed(2),
        }
      : null,
    plannedAt: item.plannedAt ? item.plannedAt.toISOString() : null,
    boughtAt: item.boughtAt ? item.boughtAt.toISOString() : null,
    createdAt: item.createdAt.toISOString(),
    updatedAt: item.updatedAt.toISOString(),
  };
}

export type SerializedWish = ReturnType<typeof serialize>;

const include = { budget: { select: planSelect } } satisfies Prisma.WishlistItemInclude;

async function assertOwned(id: string, userId: string) {
  const item = await prisma.wishlistItem.findFirst({ where: { id, userId }, include });
  if (!item) throw new NotFoundError('Wishlist item not found');
  return item as ItemRow;
}

const ORDER: Record<
  ListWishlistQuery['sort'],
  Prisma.WishlistItemOrderByWithRelationInput[]
> = {
  priority: [{ priority: 'asc' }, { createdAt: 'desc' }],
  newest: [{ createdAt: 'desc' }],
  oldest: [{ createdAt: 'asc' }],
  name: [{ name: 'asc' }],
};

export async function list(user: AuthUser, query: ListWishlistQuery) {
  const q = query.q?.trim();
  const items = (await prisma.wishlistItem.findMany({
    where: {
      userId: user.id,
      ...(query.status ? { status: query.status } : {}),
      ...(query.priority ? { priority: query.priority } : {}),
      ...(q
        ? {
            OR: [
              { name: { contains: q, mode: 'insensitive' } },
              { note: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {}),
    },
    include,
    orderBy: ORDER[query.sort],
  })) as ItemRow[];

  // Counts describe the whole list, not the filtered view, so the tabs do not
  // jump around as you search.
  const counts = await prisma.wishlistItem.groupBy({
    by: ['status'],
    where: { userId: user.id },
    _count: true,
  });
  const countOf = (s: WishlistStatus) => counts.find((c) => c.status === s)?._count ?? 0;

  return {
    items: items.map(serialize),
    stats: {
      wanting: countOf(WishlistStatus.WANTING),
      planned: countOf(WishlistStatus.PLANNED),
      bought: countOf(WishlistStatus.BOUGHT),
      dropped: countOf(WishlistStatus.DROPPED),
      total: counts.reduce((s, c) => s + c._count, 0),
    },
  };
}

/** Compact digest for the dashboard: the wants nearest the top of the pile. */
export async function dashboard(user: AuthUser) {
  const items = (await prisma.wishlistItem.findMany({
    where: {
      userId: user.id,
      status: { in: [WishlistStatus.WANTING, WishlistStatus.PLANNED] },
    },
    include,
    orderBy: [{ priority: 'asc' }, { createdAt: 'desc' }],
  })) as ItemRow[];

  const serialized = items.map(serialize);
  return {
    activeCount: serialized.length,
    plannedCount: serialized.filter((i) => i.status === WishlistStatus.PLANNED).length,
    top: serialized.slice(0, 3),
  };
}

export async function getById(user: AuthUser, id: string) {
  return serialize(await assertOwned(id, user.id));
}

export async function create(user: AuthUser, input: CreateWishlistInput) {
  const item = (await prisma.wishlistItem.create({
    data: {
      userId: user.id,
      name: input.name.trim(),
      priority: input.priority,
      note: input.note ?? null,
      link: input.link || null,
      emoji: input.emoji ?? null,
      status: input.status ?? WishlistStatus.WANTING,
    },
    include,
  })) as ItemRow;
  return serialize(item);
}

export async function update(user: AuthUser, id: string, input: UpdateWishlistInput) {
  await assertOwned(id, user.id);
  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.priority !== undefined ? { priority: input.priority } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.link !== undefined ? { link: input.link || null } : {}),
      ...(input.emoji !== undefined ? { emoji: input.emoji } : {}),
      ...(input.status !== undefined ? { status: input.status } : {}),
    },
    include,
  })) as ItemRow;
  return serialize(item);
}

/**
 * Turn a want into a budget plan. Creates the plan, links it back, and moves
 * the want to PLANNED. From here on the money is the plan's business.
 */
export async function plan(user: AuthUser, id: string, input: PlanWishlistInput) {
  const existing = await assertOwned(id, user.id);
  if (existing.budgetId) {
    throw new BadRequestError(`"${existing.name}" already has a plan behind it.`);
  }
  if (existing.status === WishlistStatus.BOUGHT) {
    throw new BadRequestError('This want is already bought.');
  }

  const created = await budgets.create(user, {
    name: (input.name ?? existing.name).trim(),
    kind: input.kind,
    recurrenceUnit: input.recurrenceUnit ?? null,
    recurrenceInterval: input.recurrenceInterval,
    plannedAmount: input.plannedAmount,
    currency: input.currency,
    categoryId: input.categoryId ?? null,
    // Carry the want's own face onto the plan so the two read as one thing.
    icon: 'sparkles',
    color: input.color ?? '#a855f7',
    note: existing.note ?? `Saving up for ${existing.name}`,
    alertThreshold: input.alertThreshold,
    startsAt: input.startsAt,
    endDate: input.endDate ?? null,
  } as never);

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: {
      budgetId: created.id,
      status: WishlistStatus.PLANNED,
      plannedAt: new Date(),
    },
    include,
  })) as ItemRow;

  await notify(
    user.id,
    'wishlist_planned',
    `"${existing.name}" now has a plan. Put money in it whenever you like.`,
    `/budgets/${created.id}`,
  );

  return { item: serialize(item), plan: created };
}

/** Break the link without deleting the plan, sending the want back to WANTING. */
export async function unlinkPlan(user: AuthUser, id: string) {
  const existing = await assertOwned(id, user.id);
  if (!existing.budgetId) throw new BadRequestError('This want has no plan linked.');

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: {
      budgetId: null,
      plannedAt: null,
      status:
        existing.status === WishlistStatus.PLANNED ? WishlistStatus.WANTING : existing.status,
    },
    include,
  })) as ItemRow;
  return serialize(item);
}

/**
 * Mark it owned. Spending happens through the plan, so this only records the
 * milestone.
 */
export async function markBought(user: AuthUser, id: string) {
  const existing = await assertOwned(id, user.id);
  if (existing.status === WishlistStatus.BOUGHT) return serialize(existing);

  const item = (await prisma.wishlistItem.update({
    where: { id },
    data: { status: WishlistStatus.BOUGHT, boughtAt: new Date() },
    include,
  })) as ItemRow;

  await notify(user.id, 'wishlist_bought', `You got "${existing.name}". Enjoy it!`, '/budgets?tab=wishlist');
  return serialize(item);
}

export async function remove(user: AuthUser, id: string) {
  await assertOwned(id, user.id);
  // The plan, if any, outlives the want: it may already hold money.
  await prisma.wishlistItem.delete({ where: { id } });
}
