/**
 * Read-only survey of the live database before any repair.
 *
 * Answers the only question that decides how to fix the shifted dates: how many
 * rows are actually wrong, rather than merely stored at an unusual time?
 *
 * A row's true calendar day is the day it fell on *locally*. The server buckets
 * by UTC day. At UTC+3 those two agree for every instant before 21:00 UTC and
 * disagree for every instant at or after it - so 21:00 is the whole boundary.
 */
import { prisma } from '../core/db.js';

const OFFSET_HOURS = Number(process.argv.find((a) => a.startsWith('--offset='))?.split('=')[1] ?? 3);
const OFFSET_MS = OFFSET_HOURS * 3_600_000;

function localDayUtc(instant: Date): Date {
  const local = new Date(instant.getTime() + OFFSET_MS);
  return new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()));
}

/** Does this row's UTC day differ from the local day the user meant? */
function isWrongDay(instant: Date): boolean {
  const utcDay = Date.UTC(
    instant.getUTCFullYear(),
    instant.getUTCMonth(),
    instant.getUTCDate(),
  );
  return localDayUtc(instant).getTime() !== utcDay;
}

async function survey(
  label: string,
  rows: Array<{ date: Date; createdAt?: Date }>,
) {
  const total = rows.length;
  const wrongDay = rows.filter((r) => isWrongDay(r.date));
  const wrongMonth = wrongDay.filter(
    (r) => localDayUtc(r.date).getUTCMonth() !== r.date.getUTCMonth(),
  );
  const atMidnight = rows.filter((r) => r.date.getUTCHours() === 0 && r.date.getUTCMinutes() === 0);
  const atNine = rows.filter((r) => r.date.getUTCHours() === 21 && r.date.getUTCMinutes() === 0);
  const atMidday = rows.filter((r) => r.date.getUTCHours() === 12);

  console.log(`\n── ${label} ${'─'.repeat(Math.max(0, 58 - label.length))}`);
  console.log(`  rows total                     ${total}`);
  console.log(`  wrong DAY  (>= 21:00 UTC)      ${wrongDay.length}`);
  console.log(`  ...of which wrong MONTH        ${wrongMonth.length}`);
  console.log(`  already at UTC midnight        ${atMidnight.length}`);
  console.log(`  at 21:00 UTC (picker-shifted)  ${atNine.length}`);
  console.log(`  at midday UTC (web-entered)    ${atMidday.length}`);

  // Hour histogram - shows at a glance where the writes cluster.
  const byHour = new Array(24).fill(0);
  for (const r of rows) byHour[r.date.getUTCHours()]! += 1;
  const peak = Math.max(...byHour, 1);
  console.log('  hour of day (UTC):');
  for (let h = 0; h < 24; h++) {
    if (byHour[h] === 0) continue;
    const bar = '█'.repeat(Math.max(1, Math.round((byHour[h]! / peak) * 34)));
    const flag = h >= 21 ? '  <- wrong day' : '';
    console.log(`    ${String(h).padStart(2, '0')}:00 ${String(byHour[h]).padStart(5)} ${bar}${flag}`);
  }

  if (wrongMonth.length > 0) {
    console.log('  examples that change month:');
    for (const r of wrongMonth.slice(0, 5)) {
      console.log(
        `    ${r.date.toISOString()}  ->  ${localDayUtc(r.date).toISOString()}`,
      );
    }
  }

  return { total, wrongDay: wrongDay.length, wrongMonth: wrongMonth.length };
}

async function main() {
  console.log(`Read-only survey. Assuming data entered at UTC+${OFFSET_HOURS}.`);

  const [users, tx, allocs, adjustments] = await Promise.all([
    prisma.user.count(),
    prisma.transaction.findMany({ select: { date: true, createdAt: true } }),
    prisma.budgetAllocation.findMany({ select: { date: true } }),
    prisma.budgetAdjustment.findMany({ select: { date: true } }),
  ]);

  console.log(`\nusers: ${users}`);

  const t = await survey('transactions.date', tx);
  const a = await survey('budget_allocations.date', allocs);
  const j = await survey('budget_adjustments.date', adjustments);

  const totalWrongDay = t.wrongDay + a.wrongDay + j.wrongDay;
  const totalWrongMonth = t.wrongMonth + a.wrongMonth + j.wrongMonth;
  const totalRows = t.total + a.total + j.total;

  console.log('\n══ verdict ═══════════════════════════════════════════════════');
  console.log(`  ${totalRows} dated rows`);
  console.log(`  ${totalWrongDay} sit on the wrong calendar day`);
  console.log(`  ${totalWrongMonth} of those are also in the wrong month`);
  if (totalWrongDay === 0) {
    console.log('\n  Nothing to repair. Every row already buckets to the day it meant.');
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
