import bcrypt from 'bcryptjs';
import { Role } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { BadRequestError, ConflictError, UnauthorizedError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from './jwt.js';
import type { LoginInput, RegisterInput } from './auth.schema.js';

const BCRYPT_ROUNDS = 12;

function toAuthUser(u: { id: string; email: string; role: Role; orgId: string }): AuthUser {
  return { id: u.id, email: u.email, role: u.role, orgId: u.orgId };
}

function issueTokens(user: AuthUser) {
  return {
    user,
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user.id),
  };
}

export async function register(input: RegisterInput) {
  const existing = await prisma.user.findUnique({ where: { email: input.email } });
  if (existing) throw new ConflictError('Email is already registered');

  const passwordHash = await bcrypt.hash(input.password, BCRYPT_ROUNDS);

  const user = await prisma.$transaction(async (tx) => {
    let orgId = input.orgId;
    let role: Role = input.orgId ? Role.RESEARCHER : Role.ADMIN;
    let inviteId: string | null = null;

    if (input.inviteToken) {
      // Accepting an invitation: join the inviter's workspace with the invited role.
      const invite = await tx.invitation.findUnique({ where: { token: input.inviteToken } });
      if (!invite || invite.status !== 'PENDING' || invite.expiresAt < new Date()) {
        throw new BadRequestError('This invitation is invalid or has expired.');
      }
      orgId = invite.orgId;
      role = invite.role;
      inviteId = invite.id;
    } else if (orgId) {
      const org = await tx.organization.findUnique({ where: { id: orgId } });
      if (!org) throw new BadRequestError('Workspace not found');
    } else {
      // No invite, no org → create a personal workspace; first user is its ADMIN.
      const org = await tx.organization.create({ data: { name: input.orgName! } });
      orgId = org.id;
    }

    const created = await tx.user.create({
      data: { name: input.name, email: input.email, passwordHash, locale: input.locale, orgId: orgId!, role },
    });

    if (inviteId) await tx.invitation.update({ where: { id: inviteId }, data: { status: 'ACCEPTED' } });
    return created;
  });

  return issueTokens(toAuthUser(user));
}

export async function login(input: LoginInput) {
  const user = await prisma.user.findUnique({ where: { email: input.email } });
  if (!user) throw new UnauthorizedError('Invalid email or password');

  const ok = await bcrypt.compare(input.password, user.passwordHash);
  if (!ok) throw new UnauthorizedError('Invalid email or password');

  return issueTokens(toAuthUser(user));
}

export async function refresh(refreshToken: string) {
  let userId: string;
  try {
    ({ userId } = verifyRefreshToken(refreshToken));
  } catch {
    throw new UnauthorizedError('Invalid or expired refresh token');
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new UnauthorizedError('User no longer exists');

  return issueTokens(toAuthUser(user));
}
