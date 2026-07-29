/**
 * Give every existing user the default categories they are missing.
 *
 * New users get the full set at registration, so this only exists to bring
 * accounts created before the list grew up to date. Idempotent: it compares
 * name+kind against what each user already has, and `skipDuplicates` covers
 * the `@@unique([userId, name, kind])` constraint either way. Categories a
 * user added themselves are never touched.
 *
 *   pnpm --filter backend db:backfill-categories
 */
import { PrismaClient } from '../generated/client/index.js';
import { DEFAULT_CATEGORIES } from '../src/modules/categories/default-categories.js';

const prisma = new PrismaClient();

async function main() {
  const users = await prisma.user.findMany({ select: { id: true, email: true } });
  console.log(
    `${users.length} user(s); ${DEFAULT_CATEGORIES.length} default categories to check against.`,
  );

  let created = 0;
  for (const user of users) {
    const existing = await prisma.category.findMany({
      where: { userId: user.id },
      select: { name: true, kind: true },
    });
    const have = new Set(existing.map((c) => `${c.kind}:${c.name.toLowerCase()}`));

    const missing = DEFAULT_CATEGORIES.filter(
      (c) => !have.has(`${c.kind}:${c.name.toLowerCase()}`),
    );
    if (missing.length === 0) {
      console.log(`  ${user.email}: already complete`);
      continue;
    }

    const res = await prisma.category.createMany({
      data: missing.map((c) => ({ ...c, userId: user.id, isDefault: true })),
      skipDuplicates: true,
    });
    created += res.count;
    console.log(`  ${user.email}: +${res.count} (${missing.map((m) => m.name).join(', ')})`);
  }

  console.log(`Done. ${created} categories created.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
