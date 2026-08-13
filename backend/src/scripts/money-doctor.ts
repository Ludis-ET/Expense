/**
 * The reconciler, from a terminal.
 *
 *   pnpm --filter @santim/backend money:doctor            # check everyone
 *   pnpm --filter @santim/backend money:doctor -- --fix   # and put it right
 *   pnpm --filter @santim/backend money:doctor -- --user <id>
 *
 * Run it before and after the money-integrity migration: the "before" tells you
 * how much existing damage there is, the "after" proves it is gone. It also runs
 * in CI against the seeded database, where any drift fails the build - which is
 * the whole point, since nothing ever checked before.
 */
import process from 'node:process';
import { prisma } from '../core/db.js';
import { logger } from '../core/logger.js';
import { inspect, repair, type DriftReport, type RepairAction } from '../core/money/reconcile.js';

function arg(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function main() {
  const shouldFix = process.argv.includes('--fix');
  const only = arg('user');

  const users = only
    ? [{ id: only, email: only }]
    : await prisma.user.findMany({ select: { id: true, email: true } });

  let unhealthy = 0;
  let repaired = 0;

  for (const user of users) {
    let report: DriftReport;
    let actions: RepairAction[] = [];

    if (shouldFix) {
      const result = await repair(user.id);
      report = result;
      actions = result.actions;
    } else {
      report = await inspect(user.id);
    }

    if (actions.length > 0) {
      repaired += 1;
      logger.info({ user: user.email }, 'repaired');
      for (const action of actions) logger.info(`  fixed  ${action.explanation}`);
    }

    if (!report.healthy) {
      unhealthy += 1;
      if (actions.length === 0) logger.warn({ user: user.email }, 'books do not balance');
      for (const v of report.violations) logger.warn(`  ${v.code}  ${v.message}`);
    }
  }

  logger.info(
    `Checked ${users.length} ${users.length === 1 ? 'account' : 'accounts'}: ` +
      `${users.length - unhealthy} balanced, ${unhealthy} not` +
      (shouldFix ? `, ${repaired} repaired` : ''),
  );

  await prisma.$disconnect();
  // A non-zero exit is what makes this useful in CI.
  process.exit(unhealthy > 0 ? 1 : 0);
}

main().catch(async (err) => {
  logger.error(err);
  await prisma.$disconnect();
  process.exit(1);
});
