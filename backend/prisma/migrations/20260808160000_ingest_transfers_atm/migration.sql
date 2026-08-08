-- Recognising the two message shapes that are not spending:
--   * cash out of an ATM  -> a transfer into the user's cash wallet
--   * money to another account -> a transfer when that account is also theirs
-- Both need a destination wallet, which is why they always reach review.

-- Which wallet holds physical cash. Nominated by the user; there is no safe
-- way to guess, and guessing wrong books withdrawals as spending.
ALTER TABLE "users" ADD COLUMN "cashAccountId" TEXT;

-- Account number as the bank writes it, usually masked. Lets a transfer
-- message be matched to one of the user's own wallets.
ALTER TABLE "accounts" ADD COLUMN "accountNumber" TEXT;

ALTER TABLE "inbox_messages" ADD COLUMN "movement" TEXT NOT NULL DEFAULT 'PLAIN';
ALTER TABLE "inbox_messages" ADD COLUMN "counterpartyAccount" TEXT;
ALTER TABLE "inbox_messages" ADD COLUMN "atmLocation" TEXT;

-- Matching an incoming counterparty account against the user's wallets.
CREATE INDEX "accounts_userId_accountNumber_idx" ON "accounts"("userId", "accountNumber");
