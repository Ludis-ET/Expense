import { Prisma } from '../core/prisma.js';
import { prisma } from './db.js';
import type { AuthUser } from './context.js';

export type RateMap = Map<string, number>;

export function rateKey(from: string, to: string): string {
  return `${from.toUpperCase()}->${to.toUpperCase()}`;
}

export async function resolveCurrency(userId: string, currency?: string): Promise<string> {
  if (currency) return currency.toUpperCase();
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { currency: true } });
  return user?.currency ?? 'ETB';
}

export async function listUserCurrencies(userId: string): Promise<string[]> {
  const [accounts, txCurrencies, ledgerCurrencies] = await Promise.all([
    prisma.account.findMany({
      where: { userId, archived: false },
      select: { currency: true },
      distinct: ['currency'],
    }),
    prisma.transaction.findMany({
      where: { userId },
      select: { currency: true },
      distinct: ['currency'],
    }),
    prisma.ledgerEntry.findMany({
      where: { userId, status: 'OPEN' },
      select: { currency: true },
      distinct: ['currency'],
    }),
  ]);

  const set = new Set<string>();
  for (const row of [...accounts, ...txCurrencies, ...ledgerCurrencies]) {
    if (row.currency) set.add(row.currency.toUpperCase());
  }

  const user = await prisma.user.findUnique({ where: { id: userId }, select: { currency: true } });
  if (user?.currency) set.add(user.currency.toUpperCase());

  return [...set].sort();
}

export async function loadRateMap(userId: string): Promise<RateMap> {
  const rows = await prisma.exchangeRate.findMany({ where: { userId } });
  const map: RateMap = new Map();
  for (const r of rows) {
    map.set(rateKey(r.fromCurrency, r.toCurrency), Number(r.rate));
  }
  return map;
}

/** Convert amount between currencies using direct or inverse user rates. Returns null if no path. */
export function convertAmount(amount: number, from: string, to: string, rates: RateMap): number | null {
  const f = from.toUpperCase();
  const t = to.toUpperCase();
  if (f === t) return amount;

  const direct = rates.get(rateKey(f, t));
  if (direct !== undefined && direct > 0) return amount * direct;

  const inverse = rates.get(rateKey(t, f));
  if (inverse !== undefined && inverse > 0) return amount / inverse;

  return null;
}

export async function convertedTotal(
  user: AuthUser,
  amounts: { currency: string; amount: number }[],
  targetCurrency?: string,
): Promise<{
  amount: string;
  baseCurrency: string;
  complete: boolean;
  missingRates: string[];
}> {
  const base = targetCurrency?.toUpperCase() ?? (await resolveCurrency(user.id));
  const rates = await loadRateMap(user.id);
  let total = 0;
  const missing = new Set<string>();

  for (const row of amounts) {
    const cur = row.currency.toUpperCase();
    if (cur === base) {
      total += row.amount;
      continue;
    }
    const converted = convertAmount(row.amount, cur, base, rates);
    if (converted === null) missing.add(cur);
    else total += converted;
  }

  return {
    amount: total.toFixed(2),
    baseCurrency: base,
    complete: missing.size === 0,
    missingRates: [...missing].sort(),
  };
}

export async function listRates(user: AuthUser) {
  const [rates, currencies] = await Promise.all([
    prisma.exchangeRate.findMany({
      where: { userId: user.id },
      orderBy: [{ fromCurrency: 'asc' }, { toCurrency: 'asc' }],
    }),
    listUserCurrencies(user.id),
  ]);

  return {
    baseCurrency: await resolveCurrency(user.id),
    currencies,
    rates: rates.map((r) => ({
      id: r.id,
      fromCurrency: r.fromCurrency,
      toCurrency: r.toCurrency,
      rate: r.rate.toString(),
      updatedAt: r.updatedAt,
    })),
  };
}

export async function upsertRates(
  user: AuthUser,
  items: { fromCurrency: string; toCurrency: string; rate: number }[],
) {
  for (const item of items) {
    const fromCurrency = item.fromCurrency.toUpperCase();
    const toCurrency = item.toCurrency.toUpperCase();
    if (fromCurrency === toCurrency) continue;
    if (!Number.isFinite(item.rate) || item.rate <= 0) continue;

    await prisma.exchangeRate.upsert({
      where: {
        userId_fromCurrency_toCurrency: { userId: user.id, fromCurrency, toCurrency },
      },
      create: {
        userId: user.id,
        fromCurrency,
        toCurrency,
        rate: new Prisma.Decimal(item.rate),
      },
      update: { rate: new Prisma.Decimal(item.rate) },
    });
  }

  return listRates(user);
}

export async function deleteRate(user: AuthUser, id: string) {
  await prisma.exchangeRate.deleteMany({ where: { id, userId: user.id } });
}
