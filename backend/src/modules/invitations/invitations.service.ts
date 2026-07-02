import { randomBytes } from 'node:crypto';
import { InvitationStatus, Role } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { env } from '../../config/env.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';

const INVITE_TTL_DAYS = 7;

export async function create(user: AuthUser, email: string, role: Role) {
  const token = randomBytes(24).toString('base64url');
  const expiresAt = new Date(Date.now() + INVITE_TTL_DAYS * 86_400_000);

  const invite = await prisma.invitation.create({
    data: { orgId: user.orgId, email: email.toLowerCase(), role, token, invitedById: user.id, expiresAt },
  });

  return { ...invite, link: `${env.APP_URL}/accept?token=${token}` };
}

export async function list(orgId: string) {
  return prisma.invitation.findMany({
    where: { orgId },
    orderBy: { createdAt: 'desc' },
    select: { id: true, email: true, role: true, status: true, createdAt: true, expiresAt: true },
  });
}

export async function revoke(user: AuthUser, id: string) {
  const invite = await prisma.invitation.findFirst({ where: { id, orgId: user.orgId } });
  if (!invite) throw new NotFoundError('Invitation not found');
  await prisma.invitation.update({ where: { id }, data: { status: InvitationStatus.REVOKED } });
}

/** Public lookup used by the accept page (no auth). */
export async function info(token: string) {
  const invite = await prisma.invitation.findUnique({
    where: { token },
    select: {
      email: true,
      status: true,
      expiresAt: true,
      org: { select: { name: true } },
      invitedBy: { select: { name: true } },
    },
  });
  if (!invite) throw new NotFoundError('Invitation not found');
  return {
    email: invite.email,
    workspace: invite.org.name,
    invitedBy: invite.invitedBy.name,
    valid: invite.status === InvitationStatus.PENDING && invite.expiresAt > new Date(),
  };
}

/** Validate a token and return the org/role to register into. Throws if unusable. */
export async function resolveForRegistration(token: string): Promise<{ orgId: string; role: Role; inviteId: string }> {
  const invite = await prisma.invitation.findUnique({ where: { token } });
  if (!invite || invite.status !== InvitationStatus.PENDING || invite.expiresAt < new Date()) {
    throw new BadRequestError('This invitation is invalid or has expired.');
  }
  return { orgId: invite.orgId, role: invite.role, inviteId: invite.id };
}
