-- Money integrity: one ledger, enforced.
--
-- Santim kept two sets of books - cash in accounts, and money reserved by plans -
-- with nothing forcing them to agree. This migration makes the agreement
-- structural: the database itself now refuses the shapes that used to corrupt the
-- books quietly.
--
-- Ordering matters. Unplanned has to be dissolved before the reservation column
-- can be made mandatory, because its rows are exactly the ones that legitimately
-- carry no reservation.

-- ---------------------------------------------------------------------------
-- 1. Replay protection
--
-- A phone that loses the reply to a queued write retries it. Without an id the
-- server can recognise, the retry books the money a second time.
-- ---------------------------------------------------------------------------

ALTER TABLE "transactions" ADD COLUMN "clientOpId" TEXT;
ALTER TABLE "budget_allocations" ADD COLUMN "clientOpId" TEXT;
ALTER TABLE "budget_adjustments" ADD COLUMN "clientOpId" TEXT;

CREATE UNIQUE INDEX "transactions_userId_clientOpId_key" ON "transactions"("userId", "clientOpId");
CREATE UNIQUE INDEX "budget_allocations_userId_clientOpId_key" ON "budget_allocations"("userId", "clientOpId");
CREATE UNIQUE INDEX "budget_adjustments_userId_clientOpId_key" ON "budget_adjustments"("userId", "clientOpId");

-- ---------------------------------------------------------------------------
-- 2. Transfers that cross a currency
--
-- Until now the destination was credited the *source* amount: moving 100 USD to
-- an ETB wallet added 100 ETB. Every balance sum now reads transferAmount, which
-- is populated for every transfer - equal to amount when both wallets share a
-- currency, and the converted figure when they do not.
-- ---------------------------------------------------------------------------

ALTER TABLE "transactions" ADD COLUMN "transferAmount" DECIMAL(14,2);
ALTER TABLE "transactions" ADD COLUMN "transferRate" DECIMAL(18,8);

-- Existing transfers were all treated as same-currency, so that is what they are.
UPDATE "transactions" SET "transferAmount" = "amount" WHERE "kind" = 'TRANSFER';

ALTER TABLE "transactions" ADD CONSTRAINT "transactions_transfer_amount_present"
  CHECK ("kind" <> 'TRANSFER' OR "transferAmount" IS NOT NULL);

-- ---------------------------------------------------------------------------
-- 3. Unplanned stops being a plan
--
-- It was a Budget row that could not be funded, closed, edited or deleted, whose
-- balance serialised as negative lifetime spend, and which six aggregates had to
-- remember to exclude. Worse, the clients disagreed about it: the web forced every
-- expense onto it, the phone sent nothing at all. Now "no plan" is one value -
-- budgetId IS NULL - decided by the server.
-- ---------------------------------------------------------------------------

UPDATE "transactions" t
SET "budgetId" = NULL, "budgetCycle" = NULL, "budgetSourceAccountId" = NULL
FROM "budgets" b
WHERE t."budgetId" = b."id" AND b."kind" = 'UNPLANNED';

-- Allocations and adjustments against Unplanned should never have existed, but
-- clear them before the cascade so nothing silently disappears with the row.
DELETE FROM "budget_allocations" a
USING "budgets" b WHERE a."budgetId" = b."id" AND b."kind" = 'UNPLANNED';

DELETE FROM "budget_adjustments" adj
USING "budgets" b WHERE adj."budgetId" = b."id" AND b."kind" = 'UNPLANNED';

UPDATE "wishlist_items" w
SET "budgetId" = NULL
FROM "budgets" b
WHERE w."budgetId" = b."id" AND b."kind" = 'UNPLANNED';

DELETE FROM "budgets" WHERE "kind" = 'UNPLANNED';

-- ---------------------------------------------------------------------------
-- 4. Every plan spend names the reservation it frees
--
-- A null here meant a spend that drained the pot but freed nothing: money counted
-- as both spent and still reserved, for good. The old SET NULL on account delete
-- created them silently.
-- ---------------------------------------------------------------------------

-- Anything still missing a source released it from the wallet it was paid out of,
-- which is what the old code assumed before the column existed.
UPDATE "transactions"
SET "budgetSourceAccountId" = "accountId"
WHERE "kind" = 'EXPENSE' AND "budgetId" IS NOT NULL AND "budgetSourceAccountId" IS NULL;

-- And nothing without a plan may carry one.
UPDATE "transactions" SET "budgetSourceAccountId" = NULL WHERE "budgetId" IS NULL;

ALTER TABLE "transactions" DROP CONSTRAINT IF EXISTS "transactions_budgetSourceAccountId_fkey";
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_budgetSourceAccountId_fkey"
  FOREIGN KEY ("budgetSourceAccountId") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- The pairing itself, as a rule the database keeps: a plan expense always names
-- a reservation, and nothing else ever does.
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_plan_spend_has_source"
  CHECK (
    ("budgetId" IS NULL AND "budgetSourceAccountId" IS NULL)
    OR ("budgetId" IS NOT NULL AND "kind" = 'EXPENSE' AND "budgetSourceAccountId" IS NOT NULL)
  );

-- ---------------------------------------------------------------------------
-- 5. Moves that must be undone as one
-- ---------------------------------------------------------------------------

ALTER TABLE "budget_allocations" ADD COLUMN "groupId" TEXT;
CREATE INDEX "budget_allocations_groupId_idx" ON "budget_allocations"("groupId");

-- Raising a plan to cover an overspend is Santim's doing, not the user's, and is
-- undone along with the spend that caused it. groupId holds that spend's id.
ALTER TABLE "budget_adjustments" ADD COLUMN "automatic" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "budget_adjustments" ADD COLUMN "groupId" TEXT;
CREATE INDEX "budget_adjustments_groupId_idx" ON "budget_adjustments"("groupId");

-- ---------------------------------------------------------------------------
-- 6. Bank-reported balances
--
-- Already parsed out of every bank message and, until now, thrown away.
-- ---------------------------------------------------------------------------

ALTER TABLE "accounts" ADD COLUMN "reportedBalance" DECIMAL(14,2);
ALTER TABLE "accounts" ADD COLUMN "reportedAt" TIMESTAMP(3);

-- ---------------------------------------------------------------------------
-- 7. Recurring rules that draw on a plan
-- ---------------------------------------------------------------------------

ALTER TABLE "recurring_rules" ADD COLUMN "budgetId" TEXT;
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- 8. Payday rules
-- ---------------------------------------------------------------------------

CREATE TYPE "FundingStepMode" AS ENUM ('FIXED', 'PERCENT', 'FILL');

CREATE TABLE "funding_rules" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "accountId" TEXT,
    "currency" TEXT NOT NULL DEFAULT 'ETB',
    "minAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "confirmFirst" BOOLEAN NOT NULL DEFAULT true,
    "lastRunAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "funding_rules_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "funding_steps" (
    "id" TEXT NOT NULL,
    "fundingRuleId" TEXT NOT NULL,
    "budgetId" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "mode" "FundingStepMode" NOT NULL DEFAULT 'FILL',
    "amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT "funding_steps_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "funding_rules_userId_active_idx" ON "funding_rules"("userId", "active");
CREATE INDEX "funding_steps_fundingRuleId_position_idx" ON "funding_steps"("fundingRuleId", "position");
CREATE INDEX "funding_steps_budgetId_idx" ON "funding_steps"("budgetId");

ALTER TABLE "funding_rules" ADD CONSTRAINT "funding_rules_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "funding_rules" ADD CONSTRAINT "funding_rules_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "funding_steps" ADD CONSTRAINT "funding_steps_fundingRuleId_fkey"
  FOREIGN KEY ("fundingRuleId") REFERENCES "funding_rules"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "funding_steps" ADD CONSTRAINT "funding_steps_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- 9. Indexes for the recent-movements feed
--
-- Undo reads the newest movements across all three tables at once.
-- ---------------------------------------------------------------------------

CREATE INDEX "transactions_userId_createdAt_idx" ON "transactions"("userId", "createdAt");
CREATE INDEX "budget_allocations_userId_createdAt_idx" ON "budget_allocations"("userId", "createdAt");
CREATE INDEX "budget_adjustments_userId_createdAt_idx" ON "budget_adjustments"("userId", "createdAt");
