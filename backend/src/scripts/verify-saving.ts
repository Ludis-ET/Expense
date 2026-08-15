/**
 * Confirms the saving-plans migration produced what it claimed, on the live
 * database. Read-only.
 *
 * The interesting one is the wishlist backfill: it is the only statement in the
 * migration that rewrote existing rows, so it is the only one whose result
 * cannot be assumed.
 */
import { prisma } from '../core/db.js';

type Row = Record<string, unknown>;
const q = (sql: string) => prisma.$queryRawUnsafe<Row[]>(sql);

let failures = 0;
const check = (label: string, ok: boolean, detail = '') => {
  if (!ok) failures += 1;
  console.log(`  [${ok ? 'OK  ' : 'FAIL'}] ${label}${detail ? `  ${detail}` : ''}`);
};

async function main() {
  console.log('columns and types');
  const cols = await q(`
    SELECT table_name, column_name, data_type, column_default
    FROM information_schema.columns
    WHERE (table_name = 'budgets' AND column_name IN ('type','goalAmount'))
       OR (table_name = 'budget_adjustments' AND column_name = 'dial')
    ORDER BY table_name, column_name
  `);
  for (const c of cols) {
    console.log(`  [OK  ] ${c.table_name}.${c.column_name}  ${c.data_type}  default=${c.column_default ?? '-'}`);
  }
  check('all three columns present', cols.length === 3, `found ${cols.length}/3`);

  const enums = await q(`
    SELECT t.typname, string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) AS labels
    FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname IN ('BudgetType','AdjustmentDial','BudgetState')
    GROUP BY t.typname ORDER BY t.typname
  `);
  console.log('\nenums');
  for (const e of enums) console.log(`  [OK  ] ${e.typname} = ${e.labels}`);
  check(
    'BudgetState gained COMPLETED',
    String(enums.find((e) => e.typname === 'BudgetState')?.labels ?? '').includes('COMPLETED'),
  );
  check('BudgetType exists', enums.some((e) => e.typname === 'BudgetType'));
  check('AdjustmentDial exists', enums.some((e) => e.typname === 'AdjustmentDial'));

  console.log('\ntables and indexes');
  // Cast: Prisma cannot deserialise a bare `regclass`.
  const tbl = await q(`SELECT to_regclass('public.budget_type_changes')::text AS t`);
  check('budget_type_changes exists', tbl[0]?.t != null);
  const idx = await q(`
    SELECT indexname FROM pg_indexes
    WHERE schemaname='public' AND indexname IN (
      'budgets_userId_type_state_idx',
      'budget_type_changes_budgetId_at_idx',
      'budget_type_changes_userId_at_idx'
    ) ORDER BY indexname
  `);
  for (const i of idx) console.log(`  [OK  ] ${i.indexname}`);
  check('all three indexes present', idx.length === 3, `found ${idx.length}/3`);

  console.log('\nexisting data');
  const spread = await q(`
    SELECT "type", count(*)::int AS n FROM budgets GROUP BY "type" ORDER BY "type"
  `);
  for (const r of spread) console.log(`  [OK  ] ${r.type}: ${r.n} plan(s)`);

  // The one rewrite in the migration. Every plan a want points at should be a
  // saving plan with the price as its finish line.
  const wl = await q(`
    SELECT count(*)::int AS total,
           count(*) FILTER (WHERE b."type" = 'SAVING')::int AS saving,
           count(*) FILTER (WHERE b."goalAmount" IS NOT NULL)::int AS withGoal
    FROM budgets b
    WHERE EXISTS (SELECT 1 FROM wishlist_items w WHERE w."budgetId" = b.id)
  `);
  // Postgres lower-cases unquoted aliases, so read them that way.
  const w = wl[0] as { total: number; saving: number; withgoal: number };
  console.log(`  wishlist-backed plans: ${w.total}`);
  check('all of them are SAVING', w.total === w.saving, `${w.saving}/${w.total}`);
  check('all of them have a goal', w.total === w.withgoal, `${w.withgoal}/${w.total}`);

  const orphan = await q(`
    SELECT count(*)::int AS n FROM budgets
    WHERE "type" = 'SPENDING' AND "goalAmount" IS NOT NULL
  `);
  check('no spending plan carries a goal', Number(orphan[0]?.n ?? -1) === 0);

  const adj = await q(`SELECT count(*)::int AS n FROM budget_adjustments WHERE dial <> 'PLANNED'`);
  check('every existing adjustment reads as PLANNED', Number(adj[0]?.n ?? -1) === 0);

  console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) FAILED.`);
  if (failures > 0) process.exitCode = 1;
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
