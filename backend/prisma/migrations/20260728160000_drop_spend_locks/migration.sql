-- Spend locks are gone. Budget plans already reserve money: filling a plan
-- takes it out of every "available" figure, which is what a lock was for.

ALTER TABLE "spend_locks" DROP CONSTRAINT IF EXISTS "spend_locks_userId_fkey";

DROP INDEX IF EXISTS "spend_locks_userId_currency_active_idx";

DROP TABLE IF EXISTS "spend_locks";

DROP TYPE IF EXISTS "SpendLockKind";
