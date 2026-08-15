-- Saving plans, beside spending plans, on one ledger.
--
-- A spending envelope and a savings goal are the same money primitive: a pot
-- funded from wallets that holds reserved money. Only the intent differs. So
-- this adds a discriminator and two amounts, and leaves the posting core, the
-- snapshot loader and every balance figure exactly as they are.
--
-- Additive throughout. No column is dropped, no row is rewritten except the
-- deliberate wishlist backfill at the end, which only ever moves rows from the
-- default SPENDING to SAVING.

-- ---------------------------------------------------------------------------
-- 1. What a plan's money is for
-- ---------------------------------------------------------------------------

CREATE TYPE "BudgetType" AS ENUM ('SPENDING', 'SAVING');

ALTER TABLE "budgets" ADD COLUMN "type" "BudgetType" NOT NULL DEFAULT 'SPENDING';

-- Every existing plan is a spending plan, which is what they have always been.
-- The default handles that without touching a row.

-- ---------------------------------------------------------------------------
-- 2. The finish line
--
-- Split from plannedAmount so a recurring saving plan can say two things at
-- once: "2,000 a month" *until* "50,000". Null means the plan runs forever -
-- the open-ended habit.
-- ---------------------------------------------------------------------------

ALTER TABLE "budgets" ADD COLUMN "goalAmount" DECIMAL(14,2);

-- ---------------------------------------------------------------------------
-- 3. Completed
--
-- Postgres will not let a new enum value be used in the same transaction that
-- adds it, so nothing below may reference 'COMPLETED'. Nothing needs to: no
-- existing row can be complete, because no existing plan is a saving plan.
-- ---------------------------------------------------------------------------

ALTER TYPE "BudgetState" ADD VALUE 'COMPLETED';

-- ---------------------------------------------------------------------------
-- 4. Which dial an adjustment moved
--
-- A recurring saving plan has two numbers that pull in opposite directions:
-- raising the contribution finishes it sooner, raising the goal finishes it
-- later. Everything written before today moved plannedAmount.
-- ---------------------------------------------------------------------------

CREATE TYPE "AdjustmentDial" AS ENUM ('PLANNED', 'GOAL');

ALTER TABLE "budget_adjustments"
  ADD COLUMN "dial" "AdjustmentDial" NOT NULL DEFAULT 'PLANNED';

-- ---------------------------------------------------------------------------
-- 5. The conversion log
--
-- Converting is meant to be repeatable, so this is a log and not a flag. It
-- moves no money - the pot keeps its balance - but it changes what every
-- number on the plan means, which is worth a record.
-- ---------------------------------------------------------------------------

CREATE TABLE "budget_type_changes" (
  "id"                 TEXT NOT NULL,
  "userId"             TEXT NOT NULL,
  "budgetId"           TEXT NOT NULL,
  "fromType"           "BudgetType" NOT NULL,
  "toType"             "BudgetType" NOT NULL,
  "balanceAtChange"    DECIMAL(14,2) NOT NULL,
  "plannedBefore"      DECIMAL(14,2) NOT NULL,
  "plannedAfter"       DECIMAL(14,2) NOT NULL,
  "goalBefore"         DECIMAL(14,2),
  "goalAfter"          DECIMAL(14,2),
  "cycleIndexAtChange" INTEGER NOT NULL DEFAULT 0,
  "reason"             TEXT,
  "at"                 TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "budget_type_changes_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "budget_type_changes_budgetId_at_idx" ON "budget_type_changes"("budgetId", "at");
CREATE INDEX "budget_type_changes_userId_at_idx"   ON "budget_type_changes"("userId", "at");

ALTER TABLE "budget_type_changes"
  ADD CONSTRAINT "budget_type_changes_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "budget_type_changes"
  ADD CONSTRAINT "budget_type_changes_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- 6. Plans filtered by what they are for
-- ---------------------------------------------------------------------------

CREATE INDEX "budgets_userId_type_state_idx" ON "budgets"("userId", "type", "state");

-- ---------------------------------------------------------------------------
-- 7. The wishlist backfill
--
-- `WishlistItem.budgetId` already existed: planning a want created a Budget,
-- which is a saving plan in everything but name. Left alone, that would have
-- shipped two features meaning "money set aside for something I want".
--
-- The boundary is now: the wishlist is the wanting, the saving plan is the
-- money. So every plan a wishlist item points at becomes a saving plan, and
-- its current planned amount becomes its finish line.
-- ---------------------------------------------------------------------------

UPDATE "budgets" b
SET "type" = 'SAVING',
    "goalAmount" = b."plannedAmount"
WHERE EXISTS (
  SELECT 1 FROM "wishlist_items" w
  WHERE w."budgetId" = b."id"
);
