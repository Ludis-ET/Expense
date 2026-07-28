-- Budgets become named spending plans (envelopes) funded from accounts.
-- Savings goals are removed entirely.

-- 1. Drop goals -----------------------------------------------------------
ALTER TABLE "recurring_rules" DROP CONSTRAINT IF EXISTS "recurring_rules_goalId_fkey";
ALTER TABLE "spend_locks" DROP CONSTRAINT IF EXISTS "spend_locks_goalId_fkey";
ALTER TABLE "wishlist_items" DROP CONSTRAINT IF EXISTS "wishlist_items_goalId_fkey";
ALTER TABLE "goal_contributions" DROP CONSTRAINT IF EXISTS "goal_contributions_goalId_fkey";
ALTER TABLE "savings_goals" DROP CONSTRAINT IF EXISTS "savings_goals_userId_fkey";

DROP INDEX IF EXISTS "recurring_rules_goalId_idx";
DROP INDEX IF EXISTS "spend_locks_goalId_idx";

-- Auto-save rules that fed a goal have no target any more. Retire them rather
-- than silently turning them into transaction-posting rules.
UPDATE "recurring_rules" SET "active" = false WHERE "goalId" IS NOT NULL;

ALTER TABLE "recurring_rules" DROP COLUMN IF EXISTS "goalId";
ALTER TABLE "spend_locks" DROP COLUMN IF EXISTS "goalId";
ALTER TABLE "wishlist_items" DROP COLUMN IF EXISTS "goalId";

DROP TABLE IF EXISTS "goal_contributions";
DROP TABLE IF EXISTS "savings_goals";

-- 2. SpendLockKind loses GOAL --------------------------------------------
UPDATE "spend_locks" SET "kind" = 'RESERVE' WHERE "kind" = 'GOAL';
ALTER TYPE "SpendLockKind" RENAME TO "SpendLockKind_old";
CREATE TYPE "SpendLockKind" AS ENUM ('FLOOR', 'RESERVE');
ALTER TABLE "spend_locks"
  ALTER COLUMN "kind" TYPE "SpendLockKind" USING ("kind"::text::"SpendLockKind");
DROP TYPE "SpendLockKind_old";

-- 3. New budget enums -----------------------------------------------------
CREATE TYPE "BudgetKind" AS ENUM ('ONE_TIME', 'RECURRING');
CREATE TYPE "BudgetState" AS ENUM ('ACTIVE', 'CLOSED');
CREATE TYPE "BudgetAllocationKind" AS ENUM ('FUND', 'RELEASE');

-- 4. Rebuild budgets ------------------------------------------------------
-- The old shape (one category-capped limit per category) has no meaningful
-- mapping onto funded plans, so old rows are dropped rather than migrated.
DROP TABLE IF EXISTS "budgets";

CREATE TABLE "budgets" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "categoryId" TEXT,
    "kind" "BudgetKind" NOT NULL DEFAULT 'ONE_TIME',
    "period" "BudgetPeriod",
    "plannedAmount" DECIMAL(14,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'ETB',
    "icon" TEXT,
    "color" TEXT,
    "note" TEXT,
    "alertThreshold" INTEGER NOT NULL DEFAULT 80,
    "state" "BudgetState" NOT NULL DEFAULT 'ACTIVE',
    "closedAt" TIMESTAMP(3),
    "cycleIndex" INTEGER NOT NULL DEFAULT 0,
    "cycleStartedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "nextResetAt" TIMESTAMP(3),
    "endDate" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "budgets_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "budgets_userId_state_idx" ON "budgets"("userId", "state");
CREATE INDEX "budgets_userId_kind_nextResetAt_idx" ON "budgets"("userId", "kind", "nextResetAt");

ALTER TABLE "budgets" ADD CONSTRAINT "budgets_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_categoryId_fkey"
  FOREIGN KEY ("categoryId") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- 5. Allocations ----------------------------------------------------------
CREATE TABLE "budget_allocations" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "budgetId" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "kind" "BudgetAllocationKind" NOT NULL DEFAULT 'FUND',
    "amount" DECIMAL(14,2) NOT NULL,
    "cycleIndex" INTEGER NOT NULL DEFAULT 0,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "budget_allocations_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "budget_allocations_budgetId_cycleIndex_idx" ON "budget_allocations"("budgetId", "cycleIndex");
CREATE INDEX "budget_allocations_userId_accountId_idx" ON "budget_allocations"("userId", "accountId");

ALTER TABLE "budget_allocations" ADD CONSTRAINT "budget_allocations_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "budget_allocations" ADD CONSTRAINT "budget_allocations_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "budget_allocations" ADD CONSTRAINT "budget_allocations_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- 6. Cycle snapshots ------------------------------------------------------
CREATE TABLE "budget_cycles" (
    "id" TEXT NOT NULL,
    "budgetId" TEXT NOT NULL,
    "index" INTEGER NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL,
    "endedAt" TIMESTAMP(3) NOT NULL,
    "label" TEXT NOT NULL,
    "plannedAmount" DECIMAL(14,2) NOT NULL,
    "carriedIn" DECIMAL(14,2) NOT NULL,
    "fundedAmount" DECIMAL(14,2) NOT NULL,
    "spentAmount" DECIMAL(14,2) NOT NULL,
    "leftoverAmount" DECIMAL(14,2) NOT NULL,
    "txCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "budget_cycles_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "budget_cycles_budgetId_index_key" ON "budget_cycles"("budgetId", "index");

ALTER TABLE "budget_cycles" ADD CONSTRAINT "budget_cycles_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- 7. Transactions can be paid out of a plan -------------------------------
ALTER TABLE "transactions" ADD COLUMN "budgetId" TEXT;
ALTER TABLE "transactions" ADD COLUMN "budgetCycle" INTEGER;

CREATE INDEX "transactions_budgetId_budgetCycle_idx" ON "transactions"("budgetId", "budgetCycle");

ALTER TABLE "transactions" ADD CONSTRAINT "transactions_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE SET NULL ON UPDATE CASCADE;
