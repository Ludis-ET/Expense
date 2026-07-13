-- AlterTable
ALTER TABLE "recurring_rules" ADD COLUMN     "goalId" TEXT,
ADD COLUMN     "wishlistItemId" TEXT;

-- CreateIndex
CREATE INDEX "recurring_rules_goalId_idx" ON "recurring_rules"("goalId");

-- CreateIndex
CREATE INDEX "recurring_rules_wishlistItemId_idx" ON "recurring_rules"("wishlistItemId");

-- AddForeignKey
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_goalId_fkey" FOREIGN KEY ("goalId") REFERENCES "savings_goals"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_wishlistItemId_fkey" FOREIGN KEY ("wishlistItemId") REFERENCES "wishlist_items"("id") ON DELETE SET NULL ON UPDATE CASCADE;
