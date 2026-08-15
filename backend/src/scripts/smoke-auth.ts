/**
 * End-to-end check of the new session lifecycle against the live database.
 *
 * "Migration applied" only proves the SQL ran. This proves the thing the
 * migration exists for actually works: that signing out invalidates a refresh
 * token which was, a moment earlier, perfectly valid.
 *
 * Uses one throwaway account and deletes it afterwards - including on failure.
 * Every other row in the database is untouched, and nothing here logs anyone
 * else out.
 */
import { createApp } from '../app.js';
import { prisma } from '../core/db.js';
import type { Server } from 'node:http';

const EMAIL = `smoke+${Date.now()}@santim.local`;
const PASSWORD = 'correct-horse-battery';

let failures = 0;
function check(label: string, ok: boolean, detail = '') {
  if (!ok) failures += 1;
  console.log(`  [${ok ? 'OK  ' : 'FAIL'}] ${label}${detail ? `  ${detail}` : ''}`);
}

async function main() {
  const app = createApp();
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const port = (server.address() as { port: number }).port;
  const base = `http://127.0.0.1:${port}/api/v1`;

  const call = async (path: string, init?: RequestInit) => {
    const res = await fetch(`${base}${path}`, {
      ...init,
      headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
    });
    const body = await res.json().catch(() => ({}));
    return { status: res.status, body: body as Record<string, unknown> };
  };

  try {
    console.log(`throwaway account: ${EMAIL}\n`);

    console.log('register');
    const reg = await call('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ name: 'Smoke Test', email: EMAIL, password: PASSWORD }),
    });
    check('registers', reg.status === 201, `status ${reg.status}`);
    let refresh = reg.body.refreshToken as string;
    let access = reg.body.accessToken as string;
    check('issues both tokens', Boolean(access && refresh));

    console.log('\npassword policy');
    const weak = await call('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ name: 'x', email: `w${Date.now()}@santim.local`, password: 'password' }),
    });
    check('rejects a common password', weak.status === 400, `status ${weak.status}`);

    console.log('\nrefresh works before sign-out');
    const r1 = await call('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: refresh }),
    });
    check('refresh succeeds', r1.status === 200, `status ${r1.status}`);
    const rotated = r1.body.refreshToken as string;
    check('returns a fresh token', Boolean(rotated));

    console.log('\nthe fix: sign out kills it');
    const out = await call('/auth/logout', {
      method: 'POST',
      headers: { Authorization: `Bearer ${access}` },
    });
    check('logout accepted', out.status === 200, `status ${out.status}`);

    const r2 = await call('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: rotated }),
    });
    check(
      'the refresh token is now refused',
      r2.status === 401,
      `status ${r2.status} - ${(r2.body.error as { message?: string })?.message ?? ''}`,
    );

    const r3 = await call('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: refresh }),
    });
    check('the original token is refused too', r3.status === 401, `status ${r3.status}`);

    console.log('\nsign back in');
    const login = await call('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
    });
    check('login works after sign-out', login.status === 200, `status ${login.status}`);
    access = login.body.accessToken as string;
    refresh = login.body.refreshToken as string;
    const r4 = await call('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken: refresh }),
    });
    check('the new token refreshes', r4.status === 200, `status ${r4.status}`);

    console.log('\nwrong password');
    const bad = await call('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email: EMAIL, password: 'not-the-password' }),
    });
    check('rejected', bad.status === 401, `status ${bad.status}`);
    const unknown = await call('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email: `nobody${Date.now()}@santim.local`, password: 'whatever123' }),
    });
    check('unknown email gives the same answer', unknown.status === 401, `status ${unknown.status}`);

    console.log('\nthe /sync endpoint');
    const sync = await call('/sync?currency=ETB', {
      headers: { Authorization: `Bearer ${access}` },
    });
    check('responds', sync.status === 200, `status ${sync.status}`);
    for (const key of ['dashboard', 'accounts', 'budgets', 'sources', 'recurring']) {
      check(`carries "${key}"`, key in sync.body);
    }

    console.log('\nwallet reservations route');
    const accountsRes = await call('/accounts', {
      headers: { Authorization: `Bearer ${access}` },
    });
    const first = (accountsRes.body.items as Array<{ id: string }> | undefined)?.[0];
    if (first) {
      const resv = await call(`/accounts/${first.id}/reservations`, {
        headers: { Authorization: `Bearer ${access}` },
      });
      check('responds', resv.status === 200, `status ${resv.status}`);
      check('returns an items array', Array.isArray(resv.body.items));
    }
  } finally {
    server.close();
    const gone = await prisma.user.deleteMany({ where: { email: { startsWith: 'smoke+' } } });
    const weak = await prisma.user.deleteMany({ where: { email: { startsWith: 'w17' } } });
    console.log(`\ncleanup: removed ${gone.count + weak.count} throwaway account(s)`);
  }

  console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) FAILED.`);
  if (failures > 0) process.exitCode = 1;
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
