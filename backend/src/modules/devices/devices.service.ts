import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { prisma } from '../../core/db.js';
import { NotFoundError, UnauthorizedError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { PairDeviceInput } from './devices.schema.js';

/**
 * Device tokens are bearer credentials with a long life, so they are stored the
 * way passwords are: only the digest. SHA-256 rather than bcrypt is the right
 * call here - the token is 32 bytes of CSPRNG output, so there is no dictionary
 * to attack and the upload path stays cheap enough to run on every request.
 */
function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

function issueToken(): string {
  return `sntm_${randomBytes(32).toString('base64url')}`;
}

function serialize(d: {
  id: string;
  name: string;
  platform: string;
  appVersion: string | null;
  lastSeenAt: Date | null;
  lastIngestAt: Date | null;
  messageCount: number;
  revokedAt: Date | null;
  createdAt: Date;
}) {
  return {
    id: d.id,
    name: d.name,
    platform: d.platform,
    appVersion: d.appVersion,
    lastSeenAt: d.lastSeenAt,
    lastIngestAt: d.lastIngestAt,
    messageCount: d.messageCount,
    revoked: d.revokedAt !== null,
    createdAt: d.createdAt,
  };
}

/**
 * Registers a phone and returns its token. The plaintext is returned exactly
 * once - there is no endpoint that can read it back, so a lost token means
 * re-pairing.
 */
export async function pair(user: AuthUser, input: PairDeviceInput) {
  const token = issueToken();

  const device = await prisma.device.create({
    data: {
      userId: user.id,
      name: input.name,
      platform: input.platform,
      appVersion: input.appVersion,
      tokenHash: hashToken(token),
      lastSeenAt: new Date(),
    },
  });

  return { device: serialize(device), deviceToken: token };
}

export async function list(user: AuthUser) {
  const devices = await prisma.device.findMany({
    where: { userId: user.id },
    orderBy: [{ revokedAt: 'asc' }, { createdAt: 'desc' }],
  });
  return { items: devices.map(serialize) };
}

/**
 * Revoking is a soft delete: the row stays so the messages it forwarded keep a
 * traceable origin, but the token stops authenticating immediately.
 */
export async function revoke(user: AuthUser, id: string) {
  const device = await prisma.device.findFirst({ where: { id, userId: user.id } });
  if (!device) throw new NotFoundError('Device not found');
  if (device.revokedAt) return serialize(device);

  const updated = await prisma.device.update({
    where: { id },
    data: {
      revokedAt: new Date(),
      // Scramble the hash so the old token can never be resurrected by
      // un-revoking, and so the unique index stays free for a re-pair.
      tokenHash: hashToken(issueToken()),
    },
  });
  return serialize(updated);
}

export async function remove(user: AuthUser, id: string) {
  const device = await prisma.device.findFirst({ where: { id, userId: user.id } });
  if (!device) throw new NotFoundError('Device not found');
  await prisma.device.delete({ where: { id } });
}

/**
 * Resolves a raw device token to its owner. Used by the ingest middleware.
 *
 * The lookup is by digest, which is a direct unique-index hit; the extra
 * constant-time compare afterwards costs nothing and keeps the code honest if
 * the storage scheme ever changes to something with collisions.
 */
export async function authenticateToken(rawToken: string) {
  const digest = hashToken(rawToken);
  const device = await prisma.device.findUnique({
    where: { tokenHash: digest },
    include: { user: { select: { id: true, email: true } } },
  });

  if (!device || device.revokedAt) throw new UnauthorizedError('Invalid or revoked device token');

  const a = Buffer.from(device.tokenHash);
  const b = Buffer.from(digest);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    throw new UnauthorizedError('Invalid or revoked device token');
  }

  return { device, user: { id: device.user.id, email: device.user.email } satisfies AuthUser };
}

/** Bookkeeping after a successful upload, for the settings panel. */
export async function recordIngest(deviceId: string, accepted: number) {
  await prisma.device.update({
    where: { id: deviceId },
    data: {
      lastSeenAt: new Date(),
      ...(accepted > 0
        ? { lastIngestAt: new Date(), messageCount: { increment: accepted } }
        : {}),
    },
  });
}
