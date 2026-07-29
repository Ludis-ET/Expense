-- Weekly snapshots, taken at the Sunday-midnight boundary. Only the current and
-- previous week are kept per user: this is a comparison aid, not an archive.
CREATE TABLE "week_snapshots" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "weekStart" TIMESTAMP(3) NOT NULL,
    "weekEnd" TIMESTAMP(3) NOT NULL,
    "currency" TEXT NOT NULL,
    "income" DECIMAL(14,2) NOT NULL,
    "expense" DECIMAL(14,2) NOT NULL,
    "net" DECIMAL(14,2) NOT NULL,
    "avgDailySpend" DECIMAL(14,2) NOT NULL,
    "txCount" INTEGER NOT NULL DEFAULT 0,
    "topCategory" TEXT,
    "topCategoryAmount" DECIMAL(14,2),
    "sealed" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "week_snapshots_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "week_snapshots_userId_currency_weekStart_key"
  ON "week_snapshots"("userId", "currency", "weekStart");
CREATE INDEX "week_snapshots_userId_weekStart_idx" ON "week_snapshots"("userId", "weekStart");

ALTER TABLE "week_snapshots" ADD CONSTRAINT "week_snapshots_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
