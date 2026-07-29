-- 1. Every user gets one built-in UNPLANNED plan that catches spending they
--    never reserved for, and existing loose expenses are filed under it.
-- 2. Recurrence becomes "every <interval> <unit>" so any cadence is expressible
--    (every 6 hours, every 3 days, every 2 weeks...), replacing BudgetPeriod.
-- 3. Plans gain a user-chosen start date instead of always starting on creation.

-- ---------------------------------------------------------------------------
-- BudgetKind gains UNPLANNED. Rebuilt rather than ALTER TYPE ... ADD VALUE,
-- because Postgres will not let a value added inside a transaction be used in
-- that same transaction - and Prisma runs each migration in one.
-- ---------------------------------------------------------------------------
ALTER TABLE "budgets" ALTER COLUMN "kind" DROP DEFAULT;

ALTER TYPE "BudgetKind" RENAME TO "BudgetKind_old";
CREATE TYPE "BudgetKind" AS ENUM ('ONE_TIME', 'RECURRING', 'UNPLANNED');
ALTER TABLE "budgets"
  ALTER COLUMN "kind" TYPE "BudgetKind" USING ("kind"::text::"BudgetKind");
DROP TYPE "BudgetKind_old";

ALTER TABLE "budgets" ALTER COLUMN "kind" SET DEFAULT 'ONE_TIME';

-- ---------------------------------------------------------------------------
-- Custom recurrence
-- ---------------------------------------------------------------------------
CREATE TYPE "RecurrenceUnit" AS ENUM ('HOUR', 'DAY', 'WEEK', 'MONTH', 'QUARTER', 'YEAR');

ALTER TABLE "budgets" ADD COLUMN "recurrenceUnit" "RecurrenceUnit";
ALTER TABLE "budgets" ADD COLUMN "recurrenceInterval" INTEGER NOT NULL DEFAULT 1;

-- Carry the old fixed periods over as an interval of 1.
UPDATE "budgets" SET "recurrenceUnit" = 'WEEK'    WHERE "period" = 'WEEKLY';
UPDATE "budgets" SET "recurrenceUnit" = 'MONTH'   WHERE "period" = 'MONTHLY';
UPDATE "budgets" SET "recurrenceUnit" = 'QUARTER' WHERE "period" = 'QUARTERLY';
UPDATE "budgets" SET "recurrenceUnit" = 'YEAR'    WHERE "period" = 'YEARLY';

ALTER TABLE "budgets" DROP COLUMN "period";
DROP TYPE "BudgetPeriod";

-- ---------------------------------------------------------------------------
-- User-chosen start date. Existing plans keep the behaviour they had, so their
-- start is the cycle they are already in.
-- ---------------------------------------------------------------------------
ALTER TABLE "budgets" ADD COLUMN "startsAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
UPDATE "budgets" SET "startsAt" = "cycleStartedAt";

-- ---------------------------------------------------------------------------
-- The built-in Unplanned plan, one per user
-- ---------------------------------------------------------------------------
INSERT INTO "budgets" (
  "id", "userId", "name", "kind", "plannedAmount", "currency",
  "icon", "color", "note", "alertThreshold", "state",
  "cycleIndex", "startsAt", "cycleStartedAt", "recurrenceInterval",
  "createdAt", "updatedAt"
)
SELECT
  'unplanned_' || u."id",
  u."id",
  'Unplanned',
  'UNPLANNED',
  0,
  u."currency",
  'circle-ellipsis',
  '#64748b',
  'Everything you spend without setting money aside first.',
  100,
  'ACTIVE',
  0,
  u."createdAt",
  u."createdAt",
  1,
  now(),
  now()
FROM "users" u
WHERE NOT EXISTS (
  SELECT 1 FROM "budgets" b WHERE b."userId" = u."id" AND b."kind" = 'UNPLANNED'
);

-- File every expense that is not already tied to a plan under Unplanned.
-- Income and transfers are left alone: a plan is a spending envelope.
UPDATE "transactions" t
SET "budgetId" = b."id", "budgetCycle" = 0
FROM "budgets" b
WHERE b."userId" = t."userId"
  AND b."kind" = 'UNPLANNED'
  AND t."budgetId" IS NULL
  AND t."kind" = 'EXPENSE';

-- Uniqueness is guaranteed by the deterministic id above: the service always
-- upserts 'unplanned_<userId>', so the primary key is the constraint. That
-- keeps it expressible in schema.prisma (a partial unique index is not).
