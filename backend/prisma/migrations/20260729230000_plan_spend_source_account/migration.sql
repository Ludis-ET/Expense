-- Which funding account's reservation a plan expense frees. Splitting this from
-- accountId lets you fill a plan from one wallet and pay from another.
ALTER TABLE "transactions" ADD COLUMN "budgetSourceAccountId" TEXT;

CREATE INDEX "transactions_budgetSourceAccountId_idx" ON "transactions"("budgetSourceAccountId");

ALTER TABLE "transactions" ADD CONSTRAINT "transactions_budgetSourceAccountId_fkey"
    FOREIGN KEY ("budgetSourceAccountId") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Until now a plan expense always left the account that funded that share, so
-- every existing row releases its reservation from the account it was charged
-- to. Unplanned holds no reservation, so it stays null.
UPDATE "transactions" t
SET "budgetSourceAccountId" = t."accountId"
FROM "budgets" b
WHERE t."budgetId" = b."id"
  AND t."kind" = 'EXPENSE'
  AND b."kind" <> 'UNPLANNED';
