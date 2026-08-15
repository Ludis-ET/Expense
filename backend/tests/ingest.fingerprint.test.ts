import { describe, expect, it } from 'vitest';
import { fingerprint, fingerprintWindow } from '../src/modules/ingest/ingest.service.js';

const USER = 'u1';
const SENDER = 'CBE';
const BODY = 'Dear customer, ETB 500.00 debited from your account. Balance: ETB 1,200.00';

const at = (iso: string) => new Date(iso);

describe('ingest fingerprint', () => {
  it('collapses the same message read twice within a minute', () => {
    // Live capture and history backfill disagreeing by a few seconds is the
    // normal case, not the edge case.
    const live = fingerprint(USER, SENDER, BODY, at('2026-08-15T10:00:12Z'));
    const backfill = fingerprint(USER, SENDER, BODY, at('2026-08-15T10:00:47Z'));
    expect(live).toBe(backfill);
  });

  it('ignores whitespace differences in the body', () => {
    const a = fingerprint(USER, SENDER, BODY, at('2026-08-15T10:00:12Z'));
    const b = fingerprint(USER, SENDER, `  ${BODY.replace(/ /g, '  ')}  `, at('2026-08-15T10:00:12Z'));
    expect(a).toBe(b);
  });

  it('separates different users, senders and bodies', () => {
    const base = fingerprint(USER, SENDER, BODY, at('2026-08-15T10:00:12Z'));
    expect(fingerprint('u2', SENDER, BODY, at('2026-08-15T10:00:12Z'))).not.toBe(base);
    expect(fingerprint(USER, 'AWASH', BODY, at('2026-08-15T10:00:12Z'))).not.toBe(base);
    expect(fingerprint(USER, SENDER, `${BODY} x`, at('2026-08-15T10:00:12Z'))).not.toBe(base);
  });

  it('does not let a field boundary be forged by a separator in the body', () => {
    // The NUL separator exists so "ab" + "c" cannot collide with "a" + "bc".
    expect(fingerprint(USER, SENDER, BODY, at('2026-08-15T10:00:12Z'))).not.toBe(
      fingerprint(USER, `${SENDER}${BODY}`, '', at('2026-08-15T10:00:12Z')),
    );
  });

  describe('the minute boundary', () => {
    // 10:00:59 and 10:01:01 are two seconds apart and land in different
    // buckets. Before the window, that produced two inbox rows for one SMS -
    // and with autoCommit on, two transactions.
    const before = at('2026-08-15T10:00:59Z');
    const after = at('2026-08-15T10:01:01Z');

    it('still hashes them differently', () => {
      expect(fingerprint(USER, SENDER, BODY, before)).not.toBe(
        fingerprint(USER, SENDER, BODY, after),
      );
    });

    it('but the window catches the neighbour either way round', () => {
      expect(fingerprintWindow(USER, SENDER, BODY, after)).toContain(
        fingerprint(USER, SENDER, BODY, before),
      );
      expect(fingerprintWindow(USER, SENDER, BODY, before)).toContain(
        fingerprint(USER, SENDER, BODY, after),
      );
    });
  });

  it('probes exactly three buckets, its own first', () => {
    const t = at('2026-08-15T10:00:30Z');
    const window = fingerprintWindow(USER, SENDER, BODY, t);
    expect(window).toHaveLength(3);
    expect(window[0]).toBe(fingerprint(USER, SENDER, BODY, t));
    expect(new Set(window).size).toBe(3);
  });

  it('does not reach two minutes out', () => {
    const t = at('2026-08-15T10:02:30Z');
    expect(fingerprintWindow(USER, SENDER, BODY, t)).not.toContain(
      fingerprint(USER, SENDER, BODY, at('2026-08-15T10:00:30Z')),
    );
  });
});
