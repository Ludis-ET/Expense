import type { CategoryKind } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { BadRequestError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateCategoryInput, UpdateCategoryInput } from './categories.schema.js';

async function assertOwnedCategory(id: string, userId: string) {
  const category = await prisma.category.findFirst({ where: { id, userId } });
  if (!category) throw new NotFoundError('Category not found');
  return category;
}

export async function list(user: AuthUser, kind?: CategoryKind) {
  const items = await prisma.category.findMany({
    where: { userId: user.id, ...(kind ? { kind } : {}) },
    orderBy: [{ kind: 'asc' }, { name: 'asc' }],
    include: { _count: { select: { transactions: true } } },
  });
  return {
    items: items.map(({ _count, ...c }) => ({ ...c, transactionCount: _count.transactions })),
  };
}

export async function create(user: AuthUser, input: CreateCategoryInput) {
  return prisma.category.create({ data: { ...input, userId: user.id } });
}

export async function update(user: AuthUser, id: string, input: UpdateCategoryInput) {
  await assertOwnedCategory(id, user.id);
  return prisma.category.update({ where: { id }, data: input });
}

export async function remove(user: AuthUser, id: string, reassignTo?: string) {
  const category = await assertOwnedCategory(id, user.id);

  const txCount = await prisma.transaction.count({ where: { categoryId: id } });
  if (txCount > 0) {
    if (!reassignTo) {
      throw new ConflictError(
        'This category has transactions. Pass reassignTo=<categoryId> to move them, or archive instead.',
      );
    }
    const target = await assertOwnedCategory(reassignTo, user.id);
    if (target.kind !== category.kind) {
      throw new BadRequestError('Transactions can only be reassigned to a category of the same kind');
    }
    await prisma.transaction.updateMany({ where: { categoryId: id }, data: { categoryId: reassignTo } });
  }

  await prisma.category.delete({ where: { id } });
}
