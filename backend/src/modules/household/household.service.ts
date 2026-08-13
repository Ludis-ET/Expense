import { InviteStatus, HouseholdRole } from '../../core/prisma.js';
import { randomBytes } from 'node:crypto';
import type { AuthUser } from '../../core/context.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, ConflictError, ForbiddenError, NotFoundError } from '../../core/errors.js';

export async function getMembership(userId: string) {
  return prisma.householdMember.findFirst({
    where: { userId },
    include: {
      household: {
        include: {
          members: {
            include: { user: { select: { id: true, name: true, email: true, avatarId: true } } },
          },
          accounts: {
            where: { archived: false },
            select: {
              id: true,
              // Whose books the wallet lives in. Balances are derived per owner,
              // because that is the scope every money figure is computed in.
              userId: true,
              name: true,
              type: true,
              currency: true,
              isShared: true,
              color: true,
              icon: true,
            },
          },
        },
      },
    },
  });
}

export async function overview(user: AuthUser) {
  const membership = await getMembership(user.id);
  if (!membership) return null;

  const sharedAccounts = membership.household.accounts.filter((a) => a.isShared);

  // This used to add up transactions by hand, and got it wrong three ways: it
  // ignored transfers entirely, ignored money reserved by plans, and summed
  // across currencies. The result disagreed with the accounts page for the very
  // same wallet. There is one balance derivation now, and this uses it.
  const { loadSnapshot, availableOf, realOf } = await import('../../core/money/index.js');
  const owners = [...new Set(sharedAccounts.map((a) => a.userId))];
  const snapshots = new Map(
    await Promise.all(owners.map(async (id) => [id, await loadSnapshot(id)] as const)),
  );

  let balance = 0;
  let realBalance = 0;
  for (const a of sharedAccounts) {
    const snap = snapshots.get(a.userId);
    if (!snap) continue;
    balance += Number(availableOf(snap, a.id));
    realBalance += Number(realOf(snap, a.id));
  }

  return {
    /** Money physically in the shared wallets, before plans reserve any of it. */
    sharedRealBalance: realBalance.toFixed(2),
    id: membership.household.id,
    name: membership.household.name,
    role: membership.role,
    members: membership.household.members.map((m) => ({
      id: m.user.id,
      name: m.user.name,
      email: m.user.email,
      avatarId: m.user.avatarId,
      role: m.role,
      isYou: m.user.id === user.id,
    })),
    sharedAccounts: membership.household.accounts.filter((a) => a.isShared),
    sharedBalance: balance.toFixed(2),
    pendingInvites: await prisma.householdInvite.count({
      where: { householdId: membership.household.id, status: InviteStatus.PENDING },
    }),
  };
}

export async function create(user: AuthUser, name?: string) {
  const existing = await getMembership(user.id);
  if (existing) throw new ConflictError('You are already in a household');

  const household = await prisma.household.create({
    data: {
      name: name?.trim() || 'Our Household',
      members: { create: { userId: user.id, role: HouseholdRole.OWNER } },
    },
    include: {
      members: { include: { user: { select: { id: true, name: true, email: true, avatarId: true } } } },
    },
  });

  return {
    id: household.id,
    name: household.name,
    members: household.members.map((m) => ({
      id: m.user.id,
      name: m.user.name,
      email: m.user.email,
      avatarId: m.user.avatarId,
      role: m.role,
      isYou: m.user.id === user.id,
    })),
  };
}

export async function invite(user: AuthUser, email: string) {
  const membership = await getMembership(user.id);
  if (!membership) throw new BadRequestError('Create a household first');
  if (membership.role !== HouseholdRole.OWNER) throw new ForbiddenError('Only the household owner can invite');

  const normalized = email.trim().toLowerCase();
  if (normalized === user.email.toLowerCase()) throw new BadRequestError('You cannot invite yourself');

  const target = await prisma.user.findUnique({ where: { email: normalized } });
  if (target) {
    const already = await prisma.householdMember.findFirst({ where: { userId: target.id } });
    if (already) throw new ConflictError('That user is already in a household');
  }

  const existing = await prisma.householdInvite.findFirst({
    where: { householdId: membership.householdId, email: normalized, status: InviteStatus.PENDING },
  });
  if (existing) throw new ConflictError('An invite is already pending for this email');

  const invite = await prisma.householdInvite.create({
    data: {
      householdId: membership.householdId,
      email: normalized,
      invitedById: user.id,
      token: randomBytes(24).toString('hex'),
      expiresAt: new Date(Date.now() + 7 * 86_400_000),
    },
  });

  return { id: invite.id, email: invite.email, token: invite.token, expiresAt: invite.expiresAt };
}

export async function acceptInvite(user: AuthUser, token: string) {
  const invite = await prisma.householdInvite.findUnique({
    where: { token },
    include: { household: true },
  });
  if (!invite || invite.status !== InviteStatus.PENDING) throw new NotFoundError('Invite not found');
  if (invite.expiresAt < new Date()) {
    await prisma.householdInvite.update({ where: { id: invite.id }, data: { status: InviteStatus.EXPIRED } });
    throw new BadRequestError('Invite has expired');
  }
  if (invite.email.toLowerCase() !== user.email.toLowerCase()) throw new ForbiddenError('This invite is for a different email');

  const existing = await getMembership(user.id);
  if (existing) throw new ConflictError('Leave your current household before joining another');

  await prisma.$transaction([
    prisma.householdMember.create({
      data: { householdId: invite.householdId, userId: user.id, role: HouseholdRole.PARTNER },
    }),
    prisma.householdInvite.update({ where: { id: invite.id }, data: { status: InviteStatus.ACCEPTED } }),
  ]);

  return { householdId: invite.householdId, name: invite.household.name };
}

export async function leave(user: AuthUser) {
  const membership = await getMembership(user.id);
  if (!membership) throw new NotFoundError('Not in a household');

  const memberCount = await prisma.householdMember.count({ where: { householdId: membership.householdId } });

  if (memberCount === 1) {
    await prisma.household.delete({ where: { id: membership.householdId } });
    return { deleted: true };
  }

  if (membership.role === HouseholdRole.OWNER) {
    const partner = await prisma.householdMember.findFirst({
      where: { householdId: membership.householdId, userId: { not: user.id } },
    });
    if (partner) {
      await prisma.householdMember.update({
        where: { id: partner.id },
        data: { role: HouseholdRole.OWNER },
      });
    }
  }

  await prisma.account.updateMany({
    where: { householdId: membership.householdId, userId: user.id },
    data: { householdId: null, isShared: false },
  });

  await prisma.householdMember.delete({ where: { id: membership.id } });
  return { deleted: false };
}

export async function shareAccount(user: AuthUser, accountId: string, shared: boolean) {
  const membership = await getMembership(user.id);
  if (!membership) throw new BadRequestError('Join or create a household to share accounts');

  const account = await prisma.account.findFirst({ where: { id: accountId, userId: user.id } });
  if (!account) throw new NotFoundError('Account not found');

  await prisma.account.update({
    where: { id: accountId },
    data: {
      isShared: shared,
      householdId: shared ? membership.householdId : null,
    },
  });

  return { id: accountId, isShared: shared };
}

export async function pendingInvitesForUser(email: string) {
  return prisma.householdInvite.findMany({
    where: { email: email.toLowerCase(), status: InviteStatus.PENDING, expiresAt: { gt: new Date() } },
    include: {
      household: { select: { name: true } },
      invitedBy: { select: { name: true } },
    },
  });
}
