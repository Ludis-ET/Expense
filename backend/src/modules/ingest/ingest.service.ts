import { createHash } from 'node:crypto';
import { InboxStatus, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import * as transactions from '../transactions/transactions.service.js';
import { recordReportedBalance } from '../accounts/accounts.service.js';
import { recordIngest } from '../devices/devices.service.js';
import type { CreateTransactionInput } from '../transactions/transactions.schema.js';
import {
  AUTO_COMMIT_MIN_CONFIDENCE,
  BANKS,
  findBankByKey,
  normalizeSender,
  parseMessage,
} from './parsers/index.js';
import type {
  ConfirmInboxInput,
  IngestBatchInput,
  ListInboxQuery,
  UpsertSenderRuleInput,
} from './ingest.schema.js';

type SenderRule = Prisma.BankSenderRuleGetPayload<object>;

const inboxInclude = {
  account: { select: { id: true, name: true, type: true, currency: true } },
  device: { select: { id: true, name: true } },
  transaction: { select: { id: true, kind: true, amount: true, date: true } },
} satisfies Prisma.InboxMessageInclude;

type InboxRow = Prisma.InboxMessageGetPayload<{ include: typeof inboxInclude }>;

function dec(v: Prisma.Decimal | null): string | null {
  return v === null ? null : v.toFixed(2);
}

function serialize(m: InboxRow, ctx?: SuggestionContext) {
  return {
    suggestion: ctx ? buildSuggestion(m, ctx) : null,
    id: m.id,
    source: m.source,
    sender: m.sender,
    body: m.body,
    receivedAt: m.receivedAt,
    status: m.status,
    bankKey: m.bankKey,
    bankLabel: m.bankKey ? (findBankByKey(m.bankKey)?.label ?? null) : null,
    parsedKind: m.parsedKind,
    parsedAmount: dec(m.parsedAmount),
    parsedCurrency: m.parsedCurrency,
    parsedBalance: dec(m.parsedBalance),
    parsedPayee: m.parsedPayee,
    parsedRef: m.parsedRef,
    occurredAt: m.occurredAt,
    movement: m.movement,
    counterpartyAccount: m.counterpartyAccount,
    atmLocation: m.atmLocation,
    confidence: m.confidence,
    account: m.account,
    device: m.device,
    transaction: m.transaction
      ? { ...m.transaction, amount: m.transaction.amount.toFixed(2) }
      : null,
    resolvedAt: m.resolvedAt,
    error: m.error,
    createdAt: m.createdAt,
  };
}

/**
 * Stable identity for a captured message, and the buckets worth checking.
 *
 * The same SMS reaches us twice by design: once live from the broadcast
 * receiver, once from a history backfill that reads a slightly different
 * timestamp off the provider. Bucketing the timestamp to the minute collapses
 * those into one row - except when the two readings straddle a minute boundary,
 * which used to produce two rows for one message (and, with autoCommit on, two
 * transactions).
 *
 * So the writer stamps the message with its own bucket, and the reader probes
 * the neighbours either side before deciding it is new.
 */
function fingerprintAt(userId: string, sender: string, body: string, bucket: number): string {
  return createHash('sha256')
    .update([userId, normalizeSender(sender), body.replace(/\s+/g, ' ').trim(), bucket].join('\u0000'))
    .digest('hex');
}

function bucketOf(receivedAt: Date): number {
  return Math.floor(receivedAt.getTime() / 60_000);
}

export function fingerprint(userId: string, sender: string, body: string, receivedAt: Date): string {
  return fingerprintAt(userId, sender, body, bucketOf(receivedAt));
}

/** This message's own fingerprint plus the two adjacent minutes. */
export function fingerprintWindow(
  userId: string,
  sender: string,
  body: string,
  receivedAt: Date,
): string[] {
  const b = bucketOf(receivedAt);
  return [b, b - 1, b + 1].map((n) => fingerprintAt(userId, sender, body, n));
}

async function rulesBySender(userId: string): Promise<Map<string, SenderRule>> {
  const rules = await prisma.bankSenderRule.findMany({ where: { userId } });
  return new Map(rules.map((r) => [normalizeSender(r.sender), r]));
}

/** Builds the right member of the transaction discriminated union. */
function buildTxInput(args: {
  kind: TxKind;
  amount: number;
  currency: string;
  date: Date;
  accountId: string;
  categoryId?: string;
  transferAccountId?: string;
  transferAmount?: number;
  budgetId?: string | null;
  budgetSourceAccountId?: string;
  payee?: string;
  note?: string;
  tags: string[];
  clientOpId?: string;
}): CreateTransactionInput {
  const base = {
    amount: args.amount,
    // The wallet's own currency wins: a message quoting a figure in another
    // denomination is a parse to fix, not a balance to corrupt.
    currency: args.currency,
    date: args.date,
    payee: args.payee,
    note: args.note,
    tags: args.tags,
    clientOpId: args.clientOpId,
  };

  if (args.kind === TxKind.TRANSFER) {
    return {
      kind: TxKind.TRANSFER,
      accountId: args.accountId,
      transferAccountId: args.transferAccountId!,
      transferAmount: args.transferAmount,
      ...base,
    };
  }
  if (args.kind === TxKind.INCOME) {
    return { kind: TxKind.INCOME, categoryId: args.categoryId!, accountId: args.accountId, ...base };
  }
  return {
    kind: TxKind.EXPENSE,
    categoryId: args.categoryId!,
    accountId: args.accountId,
    // No plan means unplanned, which is exactly what a bank message describes
    // until the user says otherwise.
    budgetId: args.budgetId ?? null,
    budgetSourceAccountId: args.budgetSourceAccountId,
    ...base,
  };
}

/** Trailing digits of an account number, ignoring masking characters. */
function accountTail(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  return digits.length >= 3 ? digits.slice(-4) : null;
}

interface SuggestionContext {
  cashAccountId: string | null;
  accounts: Array<{ id: string; name: string; accountNumber: string | null }>;
}

/**
 * What the app should offer for this message, before the user touches it.
 *
 * The two interesting cases are the ones a naive reading gets wrong: cash out
 * of an ATM is a move into the cash wallet, not spending; and money sent to an
 * account the user also owns is a transfer, not an expense. Both would
 * otherwise inflate the spending figures for money that never left.
 */
function buildSuggestion(
  m: { movement: string; counterpartyAccount: string | null; parsedKind: TxKind | null },
  ctx: SuggestionContext,
) {
  if (m.movement === 'ATM_WITHDRAWAL') {
    return ctx.cashAccountId
      ? {
          kind: TxKind.TRANSFER,
          transferAccountId: ctx.cashAccountId,
          reason: 'Cash from an ATM moves to your cash wallet - it is not spent yet.',
          needsSetup: null,
        }
      : {
          kind: TxKind.TRANSFER,
          transferAccountId: null,
          reason: 'Cash from an ATM moves to your cash wallet - it is not spent yet.',
          // Nothing to transfer into until the user says which wallet is cash.
          needsSetup: 'cashAccount' as const,
        };
  }

  if (m.movement === 'ACCOUNT_TRANSFER') {
    const tail = accountTail(m.counterpartyAccount);
    const match = tail
      ? ctx.accounts.find((a) => accountTail(a.accountNumber) === tail)
      : undefined;

    if (match) {
      return {
        kind: TxKind.TRANSFER,
        transferAccountId: match.id,
        reason: `Looks like a move to your own "${match.name}" - recorded as a transfer, not spending.`,
        needsSetup: null,
      };
    }
    // Unmatched means it probably went to someone else, which really is an
    // expense. Say so rather than silently defaulting.
    return {
      kind: m.parsedKind ?? TxKind.EXPENSE,
      transferAccountId: null,
      reason: 'Sent to an account Santim does not recognise, so it is treated as spending.',
      needsSetup: null,
    };
  }

  return { kind: m.parsedKind, transferAccountId: null, reason: null, needsSetup: null };
}

/** Loads what `buildSuggestion` needs, once per request rather than per row. */
async function suggestionContext(userId: string): Promise<SuggestionContext> {
  const [user, accounts] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { cashAccountId: true } }),
    prisma.account.findMany({
      where: { userId, archived: false },
      select: { id: true, name: true, accountNumber: true },
    }),
  ]);
  return { cashAccountId: user?.cashAccountId ?? null, accounts };
}

function noteFor(bankKey: string | null, ref: string | null): string {
  const label = bankKey ? (findBankByKey(bankKey)?.label ?? bankKey) : 'Bank message';
  return ref ? `${label} · ref ${ref}` : label;
}

// ---------------------------------------------------------------------------
// Ingest
// ---------------------------------------------------------------------------

/**
 * Accepts a batch of captured messages from a paired phone.
 *
 * Every message is answered individually so the phone can mark exactly what
 * landed and keep retrying the rest. Re-sending an already-known message is a
 * no-op that reports `duplicate` - the upload worker depends on that, since it
 * cannot distinguish "server never got it" from "reply lost on the way back".
 */
export async function ingestBatch(user: AuthUser, deviceId: string | null, input: IngestBatchInput) {
  const rules = await rulesBySender(user.id);
  const results: Array<{
    fingerprint: string;
    id: string | null;
    status: InboxStatus | 'IGNORED';
    duplicate: boolean;
    transactionId?: string;
  }> = [];

  let accepted = 0;

  /** Newest bank-reported balance seen per account in this batch. */
  const latestBalances = new Map<string, { balance: Prisma.Decimal; at: Date }>();

  for (const m of input.messages) {
    const fp = fingerprint(user.id, m.sender, m.body, m.receivedAt);

    // Probe the neighbouring minutes too: a live capture and a backfill of the
    // same message can read timestamps two seconds apart and still land in
    // different buckets.
    const existing = await prisma.inboxMessage.findFirst({
      where: {
        userId: user.id,
        fingerprint: { in: fingerprintWindow(user.id, m.sender, m.body, m.receivedAt) },
      },
      select: { id: true, status: true, transactionId: true },
    });
    if (existing) {
      results.push({
        fingerprint: fp,
        id: existing.id,
        status: existing.status,
        duplicate: true,
        ...(existing.transactionId ? { transactionId: existing.transactionId } : {}),
      });
      continue;
    }

    const rule = rules.get(normalizeSender(m.sender));
    // A sender the user explicitly switched off is dropped without a trace,
    // which is the whole point of the allowlist.
    if (rule && !rule.enabled) {
      results.push({ fingerprint: fp, id: null, status: 'IGNORED', duplicate: false });
      continue;
    }

    const parsed = parseMessage(m.sender, m.body);

    // A reference number we have already banked means the same movement
    // reached us by another route. File it, but never let it post twice.
    let status: InboxStatus = parsed ? InboxStatus.PENDING : InboxStatus.UNPARSED;
    if (parsed?.ref) {
      const seen = await prisma.inboxMessage.findFirst({
        where: {
          userId: user.id,
          parsedRef: parsed.ref,
          status: { in: [InboxStatus.PENDING, InboxStatus.CONFIRMED] },
        },
        select: { id: true },
      });
      if (seen) status = InboxStatus.DUPLICATE;
    }

    const created = await prisma.inboxMessage.create({
      data: {
        userId: user.id,
        deviceId,
        source: m.source,
        sender: m.sender,
        body: m.body,
        receivedAt: m.receivedAt,
        fingerprint: fp,
        status,
        bankKey: rule?.bankKey ?? parsed?.bankKey ?? null,
        parsedKind: parsed?.kind ?? null,
        parsedAmount: parsed?.amount ?? null,
        parsedCurrency: parsed?.currency ?? null,
        parsedBalance: parsed?.balance ?? null,
        parsedPayee: parsed?.payee ?? null,
        parsedRef: parsed?.ref ?? null,
        occurredAt: parsed?.occurredAt ?? null,
        movement: parsed?.movement ?? 'PLAIN',
        counterpartyAccount: parsed?.counterpartyAccount ?? null,
        atmLocation: parsed?.atmLocation ?? null,
        confidence: parsed?.confidence ?? 0,
        accountId: rule?.accountId ?? null,
      },
    });
    accepted += 1;

    // The bank tells us what it thinks the balance is in almost every message.
    // Keeping it is what makes drift detectable - Santim can compare its own
    // figure to the bank's and say so, instead of the two silently diverging.
    //
    // Only the newest reading per account matters, and `recordReportedBalance`
    // refuses to go backwards anyway, so a hundred-message batch collects here
    // and writes once per account below instead of once per message.
    if (parsed?.balance != null && rule?.accountId) {
      const at = parsed.occurredAt ?? m.receivedAt;
      const prev = latestBalances.get(rule.accountId);
      if (!prev || at > prev.at) {
        latestBalances.set(rule.accountId, { balance: new Prisma.Decimal(parsed.balance), at });
      }
    }

    let transactionId: string | undefined;
    if (status === InboxStatus.PENDING && rule?.autoCommit && parsed) {
      transactionId = (await tryAutoCommit(user, created.id, rule, parsed.confidence)) ?? undefined;
    }

    results.push({
      fingerprint: fp,
      id: created.id,
      status: transactionId ? InboxStatus.CONFIRMED : status,
      duplicate: false,
      ...(transactionId ? { transactionId } : {}),
    });
  }

  await Promise.all(
    [...latestBalances].map(([accountId, { balance, at }]) =>
      recordReportedBalance(user.id, accountId, balance, at),
    ),
  );

  if (deviceId) await recordIngest(deviceId, accepted);

  return { results, accepted };
}

/**
 * Posts a high-confidence message straight to the ledger.
 *
 * Deliberately conservative. Anything missing - an unmapped account, no default
 * category, a score under the floor - leaves the message in the inbox with a
 * note saying why, rather than guessing. And the write still goes through
 * `transactions.create`, so the overdraw guard and budget reservations apply
 * exactly as they would to a hand-typed entry; if the guard refuses, that
 * refusal becomes the explanation the user reads.
 */
async function tryAutoCommit(
  user: AuthUser,
  messageId: string,
  rule: SenderRule,
  confidence: number,
): Promise<string | null> {
  const msg = await prisma.inboxMessage.findUnique({ where: { id: messageId } });
  if (!msg || msg.parsedAmount === null || !msg.parsedKind) return null;

  const blockers: string[] = [];
  if (confidence < AUTO_COMMIT_MIN_CONFIDENCE) {
    blockers.push(`confidence ${confidence} is below the ${AUTO_COMMIT_MIN_CONFIDENCE} auto-post floor`);
  }
  if (!rule.accountId) blockers.push('this sender is not mapped to an account');
  if (!rule.defaultCategoryId) blockers.push('this sender has no default category');

  if (blockers.length > 0) {
    await prisma.inboxMessage.update({
      where: { id: messageId },
      data: { error: `Waiting for review: ${blockers.join('; ')}.` },
    });
    return null;
  }

  try {
    const account = await prisma.account.findFirst({
      where: { id: rule.accountId!, userId: user.id },
      select: { currency: true },
    });

    const tx = await transactions.create(
      user,
      buildTxInput({
        kind: msg.parsedKind,
        amount: Number(msg.parsedAmount),
        currency: account?.currency ?? msg.parsedCurrency ?? 'ETB',
        date: msg.occurredAt ?? msg.receivedAt,
        accountId: rule.accountId!,
        categoryId: rule.defaultCategoryId!,
        payee: msg.parsedPayee ?? undefined,
        note: noteFor(msg.bankKey, msg.parsedRef),
        tags: ['auto'],
        // The message itself is the operation: re-uploading a batch after a lost
        // reply cannot post the same movement twice.
        clientOpId: `inbox:${messageId}`,
      }),
    );

    await prisma.inboxMessage.update({
      where: { id: messageId },
      data: {
        status: InboxStatus.CONFIRMED,
        transactionId: tx.id,
        accountId: rule.accountId,
        resolvedAt: new Date(),
        error: null,
      },
    });
    return tx.id;
  } catch (err) {
    // The guard refusing is a legitimate outcome, not a crash: the message
    // stays pending and the reason is shown in the inbox.
    await prisma.inboxMessage.update({
      where: { id: messageId },
      data: { error: err instanceof Error ? err.message : 'Could not post automatically' },
    });
    return null;
  }
}

// ---------------------------------------------------------------------------
// Inbox
// ---------------------------------------------------------------------------

export async function listInbox(user: AuthUser, query: ListInboxQuery) {
  const where: Prisma.InboxMessageWhereInput = {
    userId: user.id,
    ...(query.status ? { status: query.status } : {}),
    ...(query.unresolved
      ? { status: { in: [InboxStatus.PENDING, InboxStatus.UNPARSED] } }
      : {}),
    ...(query.bankKey ? { bankKey: query.bankKey } : {}),
  };

  const [items, total, ctx] = await Promise.all([
    prisma.inboxMessage.findMany({
      where,
      orderBy: [{ receivedAt: 'desc' }, { createdAt: 'desc' }],
      skip: (query.page - 1) * query.pageSize,
      take: query.pageSize,
      include: inboxInclude,
    }),
    prisma.inboxMessage.count({ where }),
    suggestionContext(user.id),
  ]);

  return {
    items: items.map((m) => serialize(m, ctx)),
    total,
    page: query.page,
    pageSize: query.pageSize,
  };
}

export async function inboxStats(user: AuthUser) {
  const grouped = await prisma.inboxMessage.groupBy({
    by: ['status'],
    where: { userId: user.id },
    _count: { _all: true },
  });

  const counts = Object.fromEntries(
    Object.values(InboxStatus).map((s) => [s, 0]),
  ) as Record<InboxStatus, number>;
  for (const row of grouped) counts[row.status] = row._count._all;

  return { counts, needsReview: counts.PENDING + counts.UNPARSED };
}

export async function getInboxMessage(user: AuthUser, id: string) {
  const [msg, ctx] = await Promise.all([
    prisma.inboxMessage.findFirst({ where: { id, userId: user.id }, include: inboxInclude }),
    suggestionContext(user.id),
  ]);
  if (!msg) throw new NotFoundError('Message not found');
  return serialize(msg, ctx);
}

/**
 * Turns a reviewed message into a real transaction. Anything the user corrects
 * in the review sheet wins over what the parser read.
 */
export async function confirm(user: AuthUser, id: string, input: ConfirmInboxInput) {
  const msg = await prisma.inboxMessage.findFirst({ where: { id, userId: user.id } });
  if (!msg) throw new NotFoundError('Message not found');
  if (msg.status === InboxStatus.CONFIRMED && msg.transactionId) {
    throw new BadRequestError('This message has already been recorded');
  }

  const rule = await prisma.bankSenderRule.findUnique({
    where: { userId_sender: { userId: user.id, sender: msg.sender } },
  });

  const kind = input.kind ?? msg.parsedKind;
  if (!kind) throw new BadRequestError('Say whether this is money in or money out');

  const amount = input.amount ?? (msg.parsedAmount !== null ? Number(msg.parsedAmount) : undefined);
  if (amount === undefined || !(amount > 0)) throw new BadRequestError('An amount is required');

  const accountId = input.accountId ?? msg.accountId ?? rule?.accountId ?? undefined;
  if (!accountId) throw new BadRequestError('Pick which account this belongs to');

  // A transfer needs a destination instead of a category. This is the ATM path
  // - cash withdrawn has moved wallets, not left - and the own-account path.
  let transferAccountId: string | undefined;
  let categoryId: string | undefined;

  if (kind === TxKind.TRANSFER) {
    transferAccountId = input.transferAccountId ?? undefined;
    if (!transferAccountId && msg.movement === 'ATM_WITHDRAWAL') {
      const owner = await prisma.user.findUnique({
        where: { id: user.id },
        select: { cashAccountId: true },
      });
      transferAccountId = owner?.cashAccountId ?? undefined;
    }
    if (!transferAccountId) {
      throw new BadRequestError(
        msg.movement === 'ATM_WITHDRAWAL'
          ? 'Say which wallet holds your cash before recording an ATM withdrawal'
          : 'Pick which account the money went to',
      );
    }
    if (transferAccountId === accountId) {
      throw new BadRequestError('A transfer needs two different accounts');
    }
  } else {
    categoryId = input.categoryId ?? rule?.defaultCategoryId ?? undefined;
    if (!categoryId) throw new BadRequestError('Pick a category');
  }

  const account = await prisma.account.findFirst({
    where: { id: accountId, userId: user.id },
    select: { currency: true },
  });

  const tx = await transactions.create(
    user,
    buildTxInput({
      kind,
      amount,
      currency: account?.currency ?? input.currency ?? msg.parsedCurrency ?? 'ETB',
      date: input.date ?? msg.occurredAt ?? msg.receivedAt,
      accountId,
      categoryId,
      transferAccountId,
      transferAmount: input.transferAmount,
      budgetId: input.budgetId ?? null,
      budgetSourceAccountId: input.budgetSourceAccountId,
      payee: input.payee ?? msg.parsedPayee ?? undefined,
      note: input.note ?? noteFor(msg.bankKey, msg.parsedRef),
      tags: input.tags,
      clientOpId: `inbox:${msg.id}`,
    }),
  );

  // A confirmed message is also the freshest word on what the bank thinks the
  // wallet holds.
  if (msg.parsedBalance !== null) {
    await recordReportedBalance(
      user.id,
      accountId,
      msg.parsedBalance,
      msg.occurredAt ?? msg.receivedAt,
    );
  }

  const updated = await prisma.inboxMessage.update({
    where: { id },
    data: {
      status: InboxStatus.CONFIRMED,
      transactionId: tx.id,
      accountId,
      resolvedAt: new Date(),
      error: null,
    },
    include: inboxInclude,
  });

  // "Do this every time" - the fastest way for the inbox to get quieter.
  // A transfer carries no category, so it only teaches the wallet mapping.
  if (input.rememberMapping) {
    await prisma.bankSenderRule.upsert({
      where: { userId_sender: { userId: user.id, sender: msg.sender } },
      create: {
        userId: user.id,
        sender: msg.sender,
        bankKey: msg.bankKey ?? 'generic',
        accountId,
        defaultCategoryId: categoryId ?? null,
      },
      update: { accountId, ...(categoryId ? { defaultCategoryId: categoryId } : {}) },
    });
  }

  return { message: serialize(updated), transaction: tx };
}

export async function reject(user: AuthUser, id: string) {
  const msg = await prisma.inboxMessage.findFirst({ where: { id, userId: user.id } });
  if (!msg) throw new NotFoundError('Message not found');
  if (msg.transactionId) {
    throw new BadRequestError('Delete the transaction first - this message already created one');
  }

  const updated = await prisma.inboxMessage.update({
    where: { id },
    data: { status: InboxStatus.REJECTED, resolvedAt: new Date(), error: null },
    include: inboxInclude,
  });
  return serialize(updated);
}

export async function remove(user: AuthUser, id: string) {
  const msg = await prisma.inboxMessage.findFirst({ where: { id, userId: user.id } });
  if (!msg) throw new NotFoundError('Message not found');
  await prisma.inboxMessage.delete({ where: { id } });
}

/**
 * Re-runs the current parsers over messages that were never resolved.
 *
 * This is why the raw body is kept. Tighten a regex, replay, and yesterday's
 * unreadable messages become today's pending transactions - no re-uploading
 * from the phone.
 */
export async function reparse(user: AuthUser) {
  const candidates = await prisma.inboxMessage.findMany({
    where: { userId: user.id, status: { in: [InboxStatus.UNPARSED, InboxStatus.PENDING] } },
    orderBy: { receivedAt: 'desc' },
    take: 500,
  });

  let improved = 0;
  for (const msg of candidates) {
    const parsed = parseMessage(msg.sender, msg.body);
    const nextStatus = parsed ? InboxStatus.PENDING : InboxStatus.UNPARSED;

    const changed =
      (parsed?.confidence ?? 0) !== msg.confidence ||
      (parsed?.bankKey ?? null) !== msg.bankKey ||
      (parsed?.movement ?? 'PLAIN') !== msg.movement ||
      nextStatus !== msg.status;
    if (!changed) continue;

    await prisma.inboxMessage.update({
      where: { id: msg.id },
      data: {
        status: nextStatus,
        bankKey: parsed?.bankKey ?? null,
        parsedKind: parsed?.kind ?? null,
        parsedAmount: parsed?.amount ?? null,
        parsedCurrency: parsed?.currency ?? null,
        parsedBalance: parsed?.balance ?? null,
        parsedPayee: parsed?.payee ?? null,
        parsedRef: parsed?.ref ?? null,
        occurredAt: parsed?.occurredAt ?? null,
        movement: parsed?.movement ?? 'PLAIN',
        counterpartyAccount: parsed?.counterpartyAccount ?? null,
        atmLocation: parsed?.atmLocation ?? null,
        confidence: parsed?.confidence ?? 0,
      },
    });
    improved += 1;
  }

  return { scanned: candidates.length, updated: improved };
}

/** Dry-run a message through the parsers. The tuning tool. */
export function preview(sender: string, body: string) {
  const parsed = parseMessage(sender, body);
  return {
    matched: parsed !== null,
    autoCommitEligible: (parsed?.confidence ?? 0) >= AUTO_COMMIT_MIN_CONFIDENCE,
    autoCommitFloor: AUTO_COMMIT_MIN_CONFIDENCE,
    parsed: parsed
      ? { ...parsed, bankLabel: findBankByKey(parsed.bankKey)?.label ?? 'Unrecognised sender' }
      : null,
  };
}

// ---------------------------------------------------------------------------
// Sender rules
// ---------------------------------------------------------------------------

/** The bank catalog, for the app's sender picker. */
export function listBanks() {
  return {
    items: BANKS.map((b) => ({ key: b.key, label: b.label, senders: b.senders })),
  };
}

export async function listSenderRules(user: AuthUser) {
  const items = await prisma.bankSenderRule.findMany({
    where: { userId: user.id },
    orderBy: { sender: 'asc' },
    include: { account: { select: { id: true, name: true, type: true } } },
  });
  return {
    items: items.map((r) => ({
      ...r,
      bankLabel: findBankByKey(r.bankKey)?.label ?? r.bankKey,
    })),
  };
}

export async function upsertSenderRule(user: AuthUser, input: UpsertSenderRuleInput) {
  if (input.accountId) {
    const account = await prisma.account.findFirst({
      where: { id: input.accountId, userId: user.id },
      select: { id: true },
    });
    if (!account) throw new NotFoundError('Account not found');
  }
  if (input.defaultCategoryId) {
    const category = await prisma.category.findFirst({
      where: { id: input.defaultCategoryId, userId: user.id },
      select: { id: true },
    });
    if (!category) throw new NotFoundError('Category not found');
  }

  const data = {
    bankKey: input.bankKey,
    accountId: input.accountId ?? null,
    defaultCategoryId: input.defaultCategoryId ?? null,
    enabled: input.enabled,
    autoCommit: input.autoCommit,
  };

  const rule = await prisma.bankSenderRule.upsert({
    where: { userId_sender: { userId: user.id, sender: input.sender } },
    create: { userId: user.id, sender: input.sender, ...data },
    update: data,
    include: { account: { select: { id: true, name: true, type: true } } },
  });

  return { ...rule, bankLabel: findBankByKey(rule.bankKey)?.label ?? rule.bankKey };
}

export async function deleteSenderRule(user: AuthUser, id: string) {
  const rule = await prisma.bankSenderRule.findFirst({ where: { id, userId: user.id } });
  if (!rule) throw new NotFoundError('Sender rule not found');
  await prisma.bankSenderRule.delete({ where: { id } });
}

/**
 * The allowlist the phone enforces locally, so messages from anyone else never
 * leave the handset.
 */
export async function syncManifest(user: AuthUser) {
  const rules = await prisma.bankSenderRule.findMany({
    where: { userId: user.id, enabled: true },
    select: { sender: true, bankKey: true },
  });
  return {
    senders: rules.map((r) => r.sender),
    // Shipped alongside so a freshly paired phone can match known banks before
    // the user has created a single rule.
    knownSenders: BANKS.flatMap((b) => b.senders),
    updatedAt: new Date(),
  };
}
