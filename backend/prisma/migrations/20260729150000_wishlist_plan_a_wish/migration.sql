-- A want is now just an idea: emoji, name, priority, link, note. No cost, no
-- savings, no auto-save rule. When you are ready to act on one you "plan" it,
-- which creates a Budget and links the two.

-- ---------------------------------------------------------------------------
-- Recurring rules no longer fund wants
-- ---------------------------------------------------------------------------
ALTER TABLE "recurring_rules" DROP CONSTRAINT IF EXISTS "recurring_rules_wishlistItemId_fkey";
DROP INDEX IF EXISTS "recurring_rules_wishlistItemId_idx";

-- Rules that only existed to feed a want have no target any more: retire them
-- rather than silently turning them into transaction-posting rules.
UPDATE "recurring_rules" SET "active" = false WHERE "wishlistItemId" IS NOT NULL;

ALTER TABLE "recurring_rules" DROP COLUMN IF EXISTS "wishlistItemId";

-- ---------------------------------------------------------------------------
-- WishlistStatus: SAVING becomes PLANNED
-- ---------------------------------------------------------------------------
ALTER TABLE "wishlist_items" ALTER COLUMN "status" DROP DEFAULT;

ALTER TYPE "WishlistStatus" RENAME TO "WishlistStatus_old";
CREATE TYPE "WishlistStatus" AS ENUM ('WANTING', 'PLANNED', 'BOUGHT', 'DROPPED');

ALTER TABLE "wishlist_items"
  ALTER COLUMN "status" TYPE "WishlistStatus"
  USING (
    CASE "status"::text
      WHEN 'SAVING' THEN 'PLANNED'
      ELSE "status"::text
    END::"WishlistStatus"
  );

DROP TYPE "WishlistStatus_old";
ALTER TABLE "wishlist_items" ALTER COLUMN "status" SET DEFAULT 'WANTING';

-- ---------------------------------------------------------------------------
-- Drop the money, add the plan link
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS "wishlist_items_userId_currency_idx";

ALTER TABLE "wishlist_items" DROP COLUMN IF EXISTS "estimatedCost";
ALTER TABLE "wishlist_items" DROP COLUMN IF EXISTS "savedAmount";
ALTER TABLE "wishlist_items" DROP COLUMN IF EXISTS "currency";

ALTER TABLE "wishlist_items" ADD COLUMN "budgetId" TEXT;
ALTER TABLE "wishlist_items" ADD COLUMN "plannedAt" TIMESTAMP(3);
ALTER TABLE "wishlist_items" ADD COLUMN "boughtAt" TIMESTAMP(3);

CREATE INDEX "wishlist_items_budgetId_idx" ON "wishlist_items"("budgetId");

ALTER TABLE "wishlist_items" ADD CONSTRAINT "wishlist_items_budgetId_fkey"
  FOREIGN KEY ("budgetId") REFERENCES "budgets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Anything already marked PLANNED (was SAVING) has no plan behind it yet, so
-- send it back to WANTING rather than leaving a dangling promise.
UPDATE "wishlist_items" SET "status" = 'WANTING' WHERE "status" = 'PLANNED' AND "budgetId" IS NULL;
