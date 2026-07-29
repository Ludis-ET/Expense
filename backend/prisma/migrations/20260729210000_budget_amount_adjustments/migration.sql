-- Raises and cuts to a plan's amount, tracked as movements instead of edits.
CREATE TABLE "budget_adjustments" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "budgetId" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "cycleIndex" INTEGER NOT NULL DEFAULT 0,
    "reason" TEXT,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "budget_adjustments_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "budget_adjustments_budgetId_cycleIndex_idx" ON "budget_adjustments"("budgetId", "cycleIndex");

ALTER TABLE "budget_adjustments" ADD CONSTRAINT "budget_adjustments_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "budget_adjustments" ADD CONSTRAINT "budget_adjustments_budgetId_fkey"
    FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- The plan amount the current cycle opened with.
ALTER TABLE "budgets" ADD COLUMN "cycleOpeningPlanned" DECIMAL(14,2) NOT NULL DEFAULT 0;

-- Existing plans have never been adjusted, so they opened at their current amount.
UPDATE "budgets" SET "cycleOpeningPlanned" = "plannedAmount";

-- Same split for finished cycles: opening + adjusted = the plannedAmount already stored.
ALTER TABLE "budget_cycles" ADD COLUMN "openingPlanned" DECIMAL(14,2) NOT NULL DEFAULT 0,
ADD COLUMN "adjustedAmount" DECIMAL(14,2) NOT NULL DEFAULT 0;

UPDATE "budget_cycles" SET "openingPlanned" = "plannedAmount";
