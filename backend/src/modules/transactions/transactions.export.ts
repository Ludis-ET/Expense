/**
 * Getting your history out.
 *
 * Two rules shape this. First, the export accepts exactly the filters the list
 * does - it literally builds the same `where` - so "export what I am looking
 * at" cannot quietly become "export something else". Second it streams: a few
 * years of history should not become a memory spike on a small instance, so
 * rows are written to the response as they come off a cursor and never all
 * exist at once.
 *
 * The column set round-trips. `id` is included so a re-import can recognise
 * Santim's own output, and a transfer carries both figures because the two ends
 * of a cross-currency move are different numbers.
 */
import type { Response } from 'express';
import { Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import type { ExportTransactionsQuery } from './transactions.schema.js';

/** Rows fetched per round trip. Big enough to be cheap, small enough to stay flat. */
const CHUNK = 500;

/**
 * Hard ceiling on one export.
 *
 * Not a paging limit - it is the point at which a request stops being a
 * download and starts being a denial of service. Well past any real personal
 * history.
 */
const MAX_ROWS = 100_000;

const COLUMNS = [
  'id',
  'date',
  'kind',
  'amount',
  'currency',
  'account',
  'transferAccount',
  'transferAmount',
  'category',
  'plan',
  'payee',
  'note',
  'tags',
  'createdAt',
] as const;

/**
 * One CSV field.
 *
 * The leading-character guard is not cosmetic: a note beginning `=` or `+` is
 * executed as a formula when the file is opened in Excel or Sheets, which turns
 * an exported ledger into an attack on whoever opens it. Prefixing a quote
 * neutralises it while leaving the text readable.
 */
function csvField(value: unknown): string {
  if (value === null || value === undefined) return '';
  let s = String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  if (/[",\n\r]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
  return s;
}

type Row = Prisma.TransactionGetPayload<{
  include: {
    account: { select: { name: true } };
    transferAccount: { select: { name: true } };
    category: { select: { name: true } };
    budget: { select: { name: true } };
  };
}>;

function toCells(tx: Row): unknown[] {
  return [
    tx.id,
    // Date only: the ledger stores the calendar day, and a time of 00:00 on
    // every row is noise in a spreadsheet.
    tx.date.toISOString().slice(0, 10),
    tx.kind,
    tx.amount.toFixed(2),
    tx.currency,
    tx.account?.name ?? '',
    tx.transferAccount?.name ?? '',
    tx.transferAmount ? tx.transferAmount.toFixed(2) : '',
    tx.category?.name ?? '',
    tx.budget?.name ?? '',
    tx.payee ?? '',
    tx.note ?? '',
    tx.tags.join('|'),
    tx.createdAt.toISOString(),
  ];
}

/** Filename a person can find again: santim-2026-08-15.csv */
export function exportFilename(format: 'csv' | 'json', now = new Date()): string {
  return `santim-${now.toISOString().slice(0, 10)}.${format}`;
}

/**
 * Streams the filtered set to `res`.
 *
 * Keyset pagination on `(date, id)` rather than `skip`: an offset walk over a
 * large table re-scans everything it has already passed, and the cost grows
 * with each chunk. The compound cursor also keeps the order total, so no row is
 * repeated or skipped between chunks even when many share a date.
 */
export async function streamExport(
  user: AuthUser,
  query: ExportTransactionsQuery,
  where: Prisma.TransactionWhereInput,
  res: Response,
): Promise<number> {
  const json = query.format === 'json';

  res.setHeader('Content-Type', json ? 'application/json; charset=utf-8' : 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${exportFilename(query.format)}"`);
  // Nothing downstream should hold a copy of somebody's ledger.
  res.setHeader('Cache-Control', 'no-store');

  if (json) res.write('{"items":[');
  // A BOM so Excel opens UTF-8 correctly - without it Ethiopian text arrives mangled.
  else res.write(`﻿${COLUMNS.join(',')}\n`);

  let written = 0;
  let cursor: { date: Date; id: string } | null = null;

  for (;;) {
    const chunk: Row[] = await prisma.transaction.findMany({
      where: cursor
        ? {
            AND: [
              where,
              {
                OR: [
                  { date: { lt: cursor.date } },
                  { date: cursor.date, id: { gt: cursor.id } },
                ],
              },
            ],
          }
        : where,
      orderBy: [{ date: 'desc' }, { id: 'asc' }],
      take: Math.min(CHUNK, MAX_ROWS - written),
      include: {
        account: { select: { name: true } },
        transferAccount: { select: { name: true } },
        category: { select: { name: true } },
        budget: { select: { name: true } },
      },
    });

    if (chunk.length === 0) break;

    for (const tx of chunk) {
      if (json) {
        const obj = Object.fromEntries(COLUMNS.map((c, i) => [c, toCells(tx)[i]]));
        res.write(`${written === 0 ? '' : ','}${JSON.stringify(obj)}`);
      } else {
        res.write(`${toCells(tx).map(csvField).join(',')}\n`);
      }
      written += 1;
    }

    const last = chunk[chunk.length - 1]!;
    cursor = { date: last.date, id: last.id };

    if (chunk.length < CHUNK || written >= MAX_ROWS) break;
    // Let the socket drain before fetching more, so a slow client cannot make
    // the server buffer the whole export in memory.
    if (res.writableNeedDrain) {
      await new Promise<void>((resolve) => res.once('drain', resolve));
    }
  }

  if (json) {
    res.write(`],"count":${written},"exportedAt":${JSON.stringify(new Date().toISOString())}}`);
  }
  res.end();
  return written;
}

/**
 * How big an export would be, without building it.
 *
 * The sheet shows this before the user commits to a download, so "1,284
 * transactions" is a count query rather than a dry run.
 */
export async function exportPreview(where: Prisma.TransactionWhereInput) {
  const [count, span] = await Promise.all([
    prisma.transaction.count({ where }),
    prisma.transaction.aggregate({ where, _min: { date: true }, _max: { date: true } }),
  ]);
  return {
    count: Math.min(count, MAX_ROWS),
    truncated: count > MAX_ROWS,
    from: span._min.date ? span._min.date.toISOString() : null,
    to: span._max.date ? span._max.date.toISOString() : null,
    /** Rough bytes, for a "~180 KB" hint. Averaged from real rows. */
    approxBytes: Math.min(count, MAX_ROWS) * 130,
  };
}

export { TxKind };
