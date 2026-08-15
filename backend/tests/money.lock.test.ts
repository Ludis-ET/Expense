import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * A guard on the advisory-lock SQL.
 *
 * This exists because the bug it catches was invisible to every other test.
 * `withMoneyLock` shipped as:
 *
 *     pg_advisory_xact_lock(${LOCK_NAMESPACE}, hashtext(${userId}))
 *
 * Postgres has `pg_advisory_xact_lock(bigint)` and `(int, int)` - there is no
 * `(bigint, int)`. Prisma binds a JS number as bigint and `hashtext` returns
 * int, so the call resolved to no overload and *every money write failed* with
 * 42883. The unit tests all pass, because none of them execute SQL.
 *
 * Asserting on source text is crude, and it is the right trade here: the whole
 * failure mode is that nothing else looks.
 */
const source = readFileSync(
  fileURLToPath(new URL('../src/core/money/lock.ts', import.meta.url)),
  'utf8',
);

describe('withMoneyLock SQL', () => {
  it('calls the two-argument advisory lock', () => {
    expect(source).toContain('pg_advisory_xact_lock(');
    expect(source).toContain('hashtext(');
  });

  it('casts the namespace to int so an overload exists', () => {
    // Without this, the pair is (bigint, int) and Postgres has no such function.
    expect(source).toMatch(/pg_advisory_xact_lock\(\$\{LOCK_NAMESPACE\}::int\b/);
  });

  it('takes the lock inside the transaction, not outside it', () => {
    // A transaction-scoped lock released before the writes would be no lock.
    const body = source.slice(source.indexOf('prisma.$transaction'));
    const lockAt = body.indexOf('pg_advisory_xact_lock');
    const callAt = body.indexOf('return fn(tx)');
    expect(lockAt).toBeGreaterThan(-1);
    expect(callAt).toBeGreaterThan(lockAt);
  });

  it('keys the lock on the user', () => {
    expect(source).toContain('hashtext(${userId})');
  });
});
