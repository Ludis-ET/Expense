-- Add expected-outgoing tab entries (one-off bills not on recurring schedule)
ALTER TYPE "LedgerKind" ADD VALUE 'EXPECTED_OUT';
