-- Sessions that can actually be ended, notifications that stop shouting, and
-- three indexes the hot paths were missing.
--
-- Nothing here touches the ledger. Every statement is additive - no column is
-- dropped and no row is rewritten - so this migration is safe to apply to a
-- live database without a maintenance window.

-- ---------------------------------------------------------------------------
-- 1. Refresh-token revocation
--
-- Refresh tokens are stateless JWTs with a seven-day life, and there was no
-- endpoint that could invalidate one. Signing out cleared the phone and left
-- the token working. The version below is embedded in each refresh token and
-- compared when it is used, so bumping it ends every session at once.
-- ---------------------------------------------------------------------------

ALTER TABLE "users" ADD COLUMN "tokenVersion" INTEGER NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 2. Catch-up claim
--
-- The recurring and reminder catch-ups were debounced by an in-process Map:
-- it never evicted entries, and it did not hold across replicas, so two
-- instances would run the same user's catch-up simultaneously. Money survived
-- that (clientOpId makes the posting idempotent) but notifications duplicated.
-- A conditional UPDATE on this column lets exactly one caller win.
-- ---------------------------------------------------------------------------

-- Separate columns: the two sweeps are mounted on different routers, so a
-- shared stamp would let whichever claimed first starve the other for the
-- whole window.
ALTER TABLE "users" ADD COLUMN "lastCatchUpAt" TIMESTAMP(3);
ALTER TABLE "users" ADD COLUMN "lastReminderSyncAt" TIMESTAMP(3);

-- ---------------------------------------------------------------------------
-- 3. Notification dedupe + retention
--
-- A recurring rule that had been dormant for months emitted one notification
-- per missed occurrence - up to 120 in a single catch-up, which pushed every
-- real alert out of the 50-row window the app reads.
--
-- `dedupeKey` identifies the thing being announced rather than the row, so a
-- repeat upserts instead of stacking. It stays nullable: Postgres treats NULLs
-- as distinct in a unique index, so un-keyed notifications behave exactly as
-- they always did.
-- ---------------------------------------------------------------------------

ALTER TABLE "notifications" ADD COLUMN "dedupeKey" TEXT;
ALTER TABLE "notifications" ADD COLUMN "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE UNIQUE INDEX "notifications_userId_dedupeKey_key" ON "notifications"("userId", "dedupeKey");
CREATE INDEX "notifications_userId_createdAt_idx" ON "notifications"("userId", "createdAt");

-- ---------------------------------------------------------------------------
-- 4. The index the snapshot was missing
--
-- `loadSnapshot` runs on nearly every authenticated request, and one of its
-- five aggregates groups transactions by `transferAccountId`. That column was
-- the only one of the three account references without an index.
-- ---------------------------------------------------------------------------

CREATE INDEX "transactions_userId_transferAccountId_idx" ON "transactions"("userId", "transferAccountId");

-- ---------------------------------------------------------------------------
-- 5. Search that does not scan the table
--
-- Global search fires seven `ILIKE '%q%'` queries in parallel. No btree index
-- can serve a leading wildcard, so each one was a sequential scan. Trigram GIN
-- indexes can, and they are what makes the endpoint stay quick as history grows.
--
-- The extension lives in the database, not the schema file, which is why this
-- has to be hand-written SQL.
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX "transactions_note_trgm_idx"   ON "transactions" USING GIN ("note" gin_trgm_ops);
CREATE INDEX "transactions_payee_trgm_idx"  ON "transactions" USING GIN ("payee" gin_trgm_ops);
CREATE INDEX "accounts_name_trgm_idx"       ON "accounts"     USING GIN ("name" gin_trgm_ops);
CREATE INDEX "categories_name_trgm_idx"     ON "categories"   USING GIN ("name" gin_trgm_ops);
CREATE INDEX "budgets_name_trgm_idx"        ON "budgets"      USING GIN ("name" gin_trgm_ops);
