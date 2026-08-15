/**
 * End-to-end check of saving plans, conversion, averages and export against the
 * live database.
 *
 * Uses one throwaway account and deletes it afterwards, including on failure.
 * Nothing belonging to a real user is read or written.
 */
import { createApp } from '../app.js';
import { prisma } from '../core/db.js';
import type { Server } from 'node:http';

const EMAIL = `smoke-sv+${Date.now()}@santim.local`;
const PASSWORD = 'correct-horse-battery';

let failures = 0;
function check(label: string, ok: boolean, detail = '') {
  if (!ok) failures += 1;
  console.log(`  [${ok ? 'OK  ' : 'FAIL'}] ${label}${detail ? `  ${detail}` : ''}`);
}

async function main() {
  const app = createApp();
  const server: Server = await new Promise((r) => {
    const s = app.listen(0, () => r(s));
  });
  const base = `http://127.0.0.1:${(server.address() as { port: number }).port}/api/v1`;

  let token = '';
  const call = async (path: string, init?: RequestInit) => {
    const res = await fetch(`${base}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(init?.headers ?? {}),
      },
    });
    const text = await res.text();
    let body: Record<string, unknown> = {};
    try {
      body = JSON.parse(text) as Record<string, unknown>;
    } catch {
      body = { raw: text };
    }
    return { status: res.status, body, text };
  };

  try {
    const reg = await call('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ name: 'Saving Smoke', email: EMAIL, password: PASSWORD }),
    });
    token = reg.body.accessToken as string;
    check('registered', reg.status === 201, `status ${reg.status}`);

    const accounts = await call('/accounts');
    const wallet = (accounts.body.items as Array<{ id: string }>)[0]!;

    // Fund the wallet so there is something to reserve.
    const cats = await call('/categories?kind=INCOME');
    const incomeCat = (cats.body.items as Array<{ id: string }>)[0]!;
    await call('/transactions', {
      method: 'POST',
      body: JSON.stringify({
        kind: 'INCOME',
        amount: 100000,
        date: new Date().toISOString(),
        accountId: wallet.id,
        categoryId: incomeCat.id,
      }),
    });

    console.log('\none-time saving plan');
    const goal = await call('/budgets', {
      method: 'POST',
      body: JSON.stringify({
        name: 'Kenya trip',
        type: 'SAVING',
        kind: 'ONE_TIME',
        plannedAmount: 40000,
      }),
    });
    check('created', goal.status === 201, `status ${goal.status}`);
    const goalId = goal.body.id as string;
    check('is SAVING', goal.body.type === 'SAVING');
    check(
      'one-time target became the goal',
      (goal.body.saving as { goalAmount?: string })?.goalAmount === '40000.00',
    );

    console.log('\nthe cap is gone for saving');
    const over = await call(`/budgets/${goalId}/fund`, {
      method: 'POST',
      body: JSON.stringify({ accountId: wallet.id, amount: 45000 }),
    });
    check('overshooting the goal is allowed', over.status === 200, `status ${over.status}`);
    check('state flipped to COMPLETED', over.body.state === 'COMPLETED', `${over.body.state}`);

    console.log('\nspending from it is refused');
    const cats2 = await call('/categories?kind=EXPENSE');
    const expCat = (cats2.body.items as Array<{ id: string }>)[0]!;
    const spend = await call('/transactions', {
      method: 'POST',
      body: JSON.stringify({
        kind: 'EXPENSE',
        amount: 100,
        date: new Date().toISOString(),
        accountId: wallet.id,
        categoryId: expCat.id,
        budgetId: goalId,
      }),
    });
    check('refused', spend.status === 400, `status ${spend.status}`);
    check(
      'with the reason, not a generic error',
      String((spend.body.error as { message?: string })?.message ?? '').includes('saving plan'),
    );

    console.log('\nnot offered as a spend source');
    const sources = await call('/budgets/sources');
    const ids = (sources.body.items as Array<{ id: string }>).map((s) => s.id);
    check('absent from /budgets/sources', !ids.includes(goalId));

    console.log('\nraising the goal re-opens it');
    const raised = await call(`/budgets/${goalId}/adjust`, {
      method: 'POST',
      body: JSON.stringify({ direction: 'ADD', dial: 'GOAL', amount: 15000 }),
    });
    check('accepted', raised.status === 200, `status ${raised.status}`);
    check('back to ACTIVE', raised.body.state === 'ACTIVE', `${raised.body.state}`);
    check(
      'goal is now 55,000',
      (raised.body.saving as { goalAmount?: string })?.goalAmount === '55000.00',
    );

    console.log('\nrecurring habit with a finish line');
    const habit = await call('/budgets', {
      method: 'POST',
      body: JSON.stringify({
        name: 'House deposit',
        type: 'SAVING',
        kind: 'RECURRING',
        recurrenceUnit: 'MONTH',
        plannedAmount: 5000,
        goalAmount: 120000,
      }),
    });
    check('created', habit.status === 201, `status ${habit.status}`);
    const hs = habit.body.saving as { periodTarget?: string; goalAmount?: string };
    check('keeps both numbers apart', hs?.periodTarget === '5000.00' && hs?.goalAmount === '120000.00',
      `period=${hs?.periodTarget} goal=${hs?.goalAmount}`);

    console.log('\nconversion');
    const conv = await call(`/budgets/${goalId}/convert`, {
      method: 'POST',
      body: JSON.stringify({
        type: 'SPENDING',
        plannedAmount: 45000,
        kind: 'RECURRING',
        recurrenceUnit: 'MONTH',
      }),
    });
    check('converted to spending', conv.status === 200, `status ${conv.status}`);
    check('type changed', conv.body.type === 'SPENDING');
    check('saving facts are gone', conv.body.saving === null);
    check('the pot survived', conv.body.balance === '45000.00', `${conv.body.balance}`);

    const log = await call(`/budgets/${goalId}/type-changes`);
    check('the change was recorded', (log.body.items as unknown[]).length === 1);

    console.log('\nnow spendable');
    const spend2 = await call('/transactions', {
      method: 'POST',
      body: JSON.stringify({
        kind: 'EXPENSE',
        amount: 100,
        date: new Date().toISOString(),
        accountId: wallet.id,
        categoryId: expCat.id,
        budgetId: goalId,
      }),
    });
    check('the same spend now works', spend2.status === 201, `status ${spend2.status}`);

    console.log('\nper-day figures');
    const list = await call('/transactions?pageSize=5');
    const avg = list.body.averages as { days: number; spend: string; income: string } | null;
    check('returned with the list', avg != null);
    check('has a day count', (avg?.days ?? 0) >= 1, `${avg?.days} days`);

    console.log('\nexport');
    const prev = await call('/transactions/export/preview?format=csv');
    check('preview responds', prev.status === 200, `${prev.body.count} rows`);
    const csv = await call('/transactions/export?format=csv');
    check('csv streams', csv.status === 200, `${csv.text.length} bytes`);
    check('has a header row', csv.text.includes('id,date,kind,amount'));
    check('row count matches the preview',
      csv.text.trim().split('\n').length - 1 === prev.body.count,
      `${csv.text.trim().split('\n').length - 1} vs ${prev.body.count}`);
    const json = await call('/transactions/export?format=json');
    check('json streams', json.status === 200 && Array.isArray(json.body.items));
  } finally {
    server.close();
    const gone = await prisma.user.deleteMany({ where: { email: { startsWith: 'smoke-sv+' } } });
    console.log(`\ncleanup: removed ${gone.count} throwaway account(s)`);
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
