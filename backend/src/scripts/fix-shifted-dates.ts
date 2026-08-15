/**
 * Repair dates that were stored a day early.
 *
 * The phone's date picker returns local midnight, and `.toUtc()` on that in
 * Ethiopia (UTC+3) rewound it to 21:00 the previous day. Every date the user
 * picked was therefore stored as the day before, and the server - which buckets
 * every day, week and month boundary in UTC - filed it under the wrong period.
 * Picking 1 September counted against August.
 *
 * The clients no longer do this (see `wireDate`), so new rows are already
 * correct. This script fixes the ones written before that.
 *
 * ## Status: not needed against production, as of 2026-08-15
 *
 * The survey in `inspect-dates.ts` found **zero** affected rows across all 332
 * dated records. The tell was the hour histogram: not one row sits at 21:00
 * UTC, and 175 of 291 transactions sit at exactly UTC midnight - which is what
 * `localMidnight.toUtc()` produces on a device whose clock is set to **UTC**,
 * not to EAT. Comparing `date` against `createdAt` confirmed it: a row picked
 * as 12 August and written at 17:05 UTC stored `2026-08-12T00:00:00Z`, where an
 * EAT device would have stored `2026-08-11T21:00:00Z`.
 *
 * So the defect is real in the code and would have bitten the first device set
 * to Ethiopian time - but it never fired against this data, and running this
 * script would have rewritten 116 correct rows for no gain.
 *
 * Keep it. It is the right tool if an older APK is ever used on a device with a
 * non-UTC clock, and `inspect-dates.ts` is how you find out whether it is.
 *
 * ## The transform
 *
 * Shift the stored instant into local time, then truncate to midnight and store
 * that as UTC. `2026-08-31T21:00:00Z` + 3h is `2026-09-01T00:00`, so it becomes
 * `2026-09-01T00:00:00Z` - the day the user actually picked.
 *
 * It is **idempotent**: a row already at UTC midnight shifts to 03:00 local,
 * truncates back to the same midnight, and does not move. Re-running is safe,
 * and so is running it after the client fix has already shipped.
 *
 * ## Running it
 *
 *   pnpm --filter @santim/backend exec tsx src/scripts/fix-shifted-dates.ts            # dry run
 *   pnpm --filter @santim/backend exec tsx src/scripts/fix-shifted-dates.ts --apply    # write
 *
 * Options:
 *   --offset=3     hours east of UTC the data was entered in (default 3, EAT)
 *   --user=<id>    limit to one user
 *
 * Take a database backup first. This rewrites a column the whole app reads.
 */
import { prisma } from '../core/db.js';

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const OFFSET_HOURS = Number(args.find((a) => a.startsWith('--offset='))?.split('=')[1] ?? 3);
const ONLY_USER = args.find((a) => a.startsWith('--user='))?.split('=')[1];

if (!Number.isFinite(OFFSET_HOURS) || Math.abs(OFFSET_HOURS) > 14) {
  console.error(`--offset must be hours between -14 and 14, got ${OFFSET_HOURS}`);
  process.exit(1);
}

const OFFSET_MS = OFFSET_HOURS * 3_600_000;

/** The calendar day this instant fell on locally, as UTC midnight. */
function localDayUtc(instant: Date): Date {
  const local = new Date(instant.getTime() + OFFSET_MS);
  return new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()));
}

const where = ONLY_USER ? { userId: ONLY_USER } : {};

/** One table's date column. */
interface Target {
  label: string;
  load: () => Promise<Array<{ id: string; value: Date | null }>>;
  save: (id: string, value: Date) => Promise<unknown>;
}

const targets: Target[] = [
  {
    label: 'transactions.date',
    load: () =>
      prisma.transaction
        .findMany({ where, select: { id: true, date: true } })
        .then((rows) => rows.map((r) => ({ id: r.id, value: r.date }))),
    save: (id, date) => prisma.transaction.update({ where: { id }, data: { date } }),
  },
  {
    label: 'budget_allocations.date',
    load: () =>
      prisma.budgetAllocation
        .findMany({ where, select: { id: true, date: true } })
        .then((rows) => rows.map((r) => ({ id: r.id, value: r.date }))),
    save: (id, date) => prisma.budgetAllocation.update({ where: { id }, data: { date } }),
  },
  {
    label: 'budget_adjustments.date',
    load: () =>
      prisma.budgetAdjustment
        .findMany({ where, select: { id: true, date: true } })
        .then((rows) => rows.map((r) => ({ id: r.id, value: r.date }))),
    save: (id, date) => prisma.budgetAdjustment.update({ where: { id }, data: { date } }),
  },
];

async function main() {
  console.log(
    `${APPLY ? 'APPLYING' : 'DRY RUN'} - assuming data was entered at UTC+${OFFSET_HOURS}` +
      `${ONLY_USER ? ` for user ${ONLY_USER}` : ''}\n`,
  );

  let grandTotal = 0;
  let grandMoved = 0;

  for (const target of targets) {
    const rows = await target.load();
    const moves = rows.flatMap((r) => {
      if (!r.value) return [];
      const next = localDayUtc(r.value);
      return next.getTime() === r.value.getTime() ? [] : [{ id: r.id, from: r.value, to: next }];
    });

    grandTotal += rows.length;
    grandMoved += moves.length;

    console.log(`${target.label}: ${moves.length} of ${rows.length} rows would move`);
    for (const m of moves.slice(0, 3)) {
      console.log(`    ${m.from.toISOString()}  ->  ${m.to.toISOString()}`);
    }
    if (moves.length > 3) console.log(`    ... and ${moves.length - 3} more`);

    if (APPLY && moves.length > 0) {
      // Sequential on purpose: this is a one-off repair, not a hot path, and a
      // predictable trickle is easier on a small database than a burst.
      let done = 0;
      for (const m of moves) {
        await target.save(m.id, m.to);
        if (++done % 200 === 0) console.log(`    ...${done}/${moves.length}`);
      }
      console.log(`    written: ${done}`);
    }
    console.log();
  }

  console.log(`${grandMoved} of ${grandTotal} dated rows ${APPLY ? 'moved' : 'would move'}.`);
  if (!APPLY && grandMoved > 0) console.log('Re-run with --apply once you have a backup.');
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
