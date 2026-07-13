-- CreateEnum
CREATE TYPE "SpendLockKind" AS ENUM ('FLOOR', 'GOAL', 'RESERVE');

-- CreateEnum
CREATE TYPE "WishlistStatus" AS ENUM ('WANTING', 'SAVING', 'BOUGHT', 'DROPPED');

-- CreateTable
CREATE TABLE "spend_locks" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" "SpendLockKind" NOT NULL,
    "name" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'ETB',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "note" TEXT,
    "goalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "spend_locks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "wishlist_items" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "estimatedCost" DECIMAL(14,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'ETB',
    "priority" INTEGER NOT NULL DEFAULT 3,
    "status" "WishlistStatus" NOT NULL DEFAULT 'WANTING',
    "note" TEXT,
    "link" TEXT,
    "emoji" TEXT,
    "savedAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "goalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "wishlist_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "spend_locks_userId_currency_active_idx" ON "spend_locks"("userId", "currency", "active");

-- CreateIndex
CREATE INDEX "spend_locks_goalId_idx" ON "spend_locks"("goalId");

-- CreateIndex
CREATE INDEX "wishlist_items_userId_status_idx" ON "wishlist_items"("userId", "status");

-- CreateIndex
CREATE INDEX "wishlist_items_userId_currency_idx" ON "wishlist_items"("userId", "currency");

-- AddForeignKey
ALTER TABLE "spend_locks" ADD CONSTRAINT "spend_locks_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "spend_locks" ADD CONSTRAINT "spend_locks_goalId_fkey" FOREIGN KEY ("goalId") REFERENCES "savings_goals"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wishlist_items" ADD CONSTRAINT "wishlist_items_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wishlist_items" ADD CONSTRAINT "wishlist_items_goalId_fkey" FOREIGN KEY ("goalId") REFERENCES "savings_goals"("id") ON DELETE SET NULL ON UPDATE CASCADE;
