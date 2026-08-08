-- Bank-message capture: paired phones, a sender allowlist, and the review inbox
-- that parsed messages land in before they become transactions.

CREATE TYPE "MessageSource" AS ENUM ('SMS', 'NOTIFICATION', 'MANUAL', 'EMAIL');
CREATE TYPE "InboxStatus" AS ENUM ('PENDING', 'CONFIRMED', 'REJECTED', 'UNPARSED', 'DUPLICATE');

-- A paired phone. Only the SHA-256 of the device token is stored.
CREATE TABLE "devices" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "platform" TEXT NOT NULL DEFAULT 'android',
    "tokenHash" TEXT NOT NULL,
    "appVersion" TEXT,
    "lastSeenAt" TIMESTAMP(3),
    "lastIngestAt" TIMESTAMP(3),
    "messageCount" INTEGER NOT NULL DEFAULT 0,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "devices_tokenHash_key" ON "devices"("tokenHash");
CREATE INDEX "devices_userId_revokedAt_idx" ON "devices"("userId", "revokedAt");

-- Which SMS senders count as a bank, and what to do with their messages.
CREATE TABLE "bank_sender_rules" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "bankKey" TEXT NOT NULL,
    "sender" TEXT NOT NULL,
    "accountId" TEXT,
    "defaultCategoryId" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "autoCommit" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "bank_sender_rules_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "bank_sender_rules_userId_sender_key" ON "bank_sender_rules"("userId", "sender");
CREATE INDEX "bank_sender_rules_userId_enabled_idx" ON "bank_sender_rules"("userId", "enabled");

-- One captured message plus whatever the parser made of it. The raw body is
-- kept so a parser fix can be replayed over history.
CREATE TABLE "inbox_messages" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "deviceId" TEXT,
    "source" "MessageSource" NOT NULL DEFAULT 'SMS',
    "sender" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL,
    "fingerprint" TEXT NOT NULL,
    "status" "InboxStatus" NOT NULL DEFAULT 'PENDING',
    "bankKey" TEXT,
    "parsedKind" "TxKind",
    "parsedAmount" DECIMAL(14,2),
    "parsedCurrency" TEXT,
    "parsedBalance" DECIMAL(14,2),
    "parsedPayee" TEXT,
    "parsedRef" TEXT,
    "occurredAt" TIMESTAMP(3),
    "confidence" INTEGER NOT NULL DEFAULT 0,
    "accountId" TEXT,
    "transactionId" TEXT,
    "resolvedAt" TIMESTAMP(3),
    "error" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "inbox_messages_pkey" PRIMARY KEY ("id")
);

-- The idempotency guarantee the phone's retry loop depends on.
CREATE UNIQUE INDEX "inbox_messages_userId_fingerprint_key" ON "inbox_messages"("userId", "fingerprint");
CREATE UNIQUE INDEX "inbox_messages_transactionId_key" ON "inbox_messages"("transactionId");
CREATE INDEX "inbox_messages_userId_status_receivedAt_idx" ON "inbox_messages"("userId", "status", "receivedAt");
CREATE INDEX "inbox_messages_userId_parsedRef_idx" ON "inbox_messages"("userId", "parsedRef");

ALTER TABLE "devices" ADD CONSTRAINT "devices_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "bank_sender_rules" ADD CONSTRAINT "bank_sender_rules_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "bank_sender_rules" ADD CONSTRAINT "bank_sender_rules_accountId_fkey"
    FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "inbox_messages" ADD CONSTRAINT "inbox_messages_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "inbox_messages" ADD CONSTRAINT "inbox_messages_deviceId_fkey"
    FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "inbox_messages" ADD CONSTRAINT "inbox_messages_accountId_fkey"
    FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "inbox_messages" ADD CONSTRAINT "inbox_messages_transactionId_fkey"
    FOREIGN KEY ("transactionId") REFERENCES "transactions"("id") ON DELETE SET NULL ON UPDATE CASCADE;
