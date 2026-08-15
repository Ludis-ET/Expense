/**
 * A before/after fingerprint of the live database. Read-only.
 *
 * The migration is additive, so every one of these numbers must be identical
 * on both sides of it. Anything that moves is a bug in the migration, and this
 * is how that gets noticed rather than assumed.
 */
import { prisma } from '../core/db.js';

async function main() {
  const [
    users,
    accounts,
    transactions,
    allocations,
    adjustments,
    budgets,
    categories,
    notifications,
    ledgerEntries,
    inbox,
    devices,
  ] = await Promise.all([
    prisma.user.count(),
    prisma.account.count(),
    prisma.transaction.count(),
    prisma.budgetAllocation.count(),
    prisma.budgetAdjustment.count(),
    prisma.budget.count(),
    prisma.category.count(),
    prisma.notification.count(),
    prisma.ledgerEntry.count(),
    prisma.inboxMessage.count(),
    prisma.device.count(),
  ]);

  // Money totals, because a row count alone would not catch a mangled Decimal.
  const sums = await prisma.transaction.groupBy({
    by: ['kind'],
    _sum: { amount: true, transferAmount: true },
  });
  const allocSum = await prisma.budgetAllocation.aggregate({ _sum: { amount: true } });

  console.log('counts');
  console.table({
    users, accounts, transactions, allocations, adjustments,
    budgets, categories, notifications, ledgerEntries, inbox, devices,
  });

  console.log('money totals');
  for (const s of sums) {
    console.log(
      `  ${s.kind.padEnd(9)} amount=${s._sum.amount?.toFixed(2) ?? '0.00'}` +
        `  transferAmount=${s._sum.transferAmount?.toFixed(2) ?? 'null'}`,
    );
  }
  console.log(`  ALLOCATIONS amount=${allocSum._sum.amount?.toFixed(2) ?? '0.00'}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
