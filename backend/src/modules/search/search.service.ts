import { prisma } from '../../core/db.js';
import { GUIDES } from '../guides/guides.content.js';

export type SearchHitType =
  | 'transaction'
  | 'budget'
  | 'account'
  | 'category'
  | 'recurring'
  | 'wishlist'
  | 'ledger'
  | 'guide'
  | 'command';

export interface SearchHit {
  id: string;
  type: SearchHitType;
  title: string;
  subtitle?: string;
  amount?: string;
  currency?: string;
  icon?: string | null;
  color?: string | null;
  /** Deep-link contract for clients. */
  href: { screen: string; id?: string; params?: Record<string, string> };
  score: number;
  matchFields: string[];
}

export interface SearchGroup {
  type: SearchHitType;
  label: string;
  items: SearchHit[];
}

const LABELS: Record<SearchHitType, string> = {
  transaction: 'Transactions',
  budget: 'Plans',
  account: 'Wallets',
  category: 'Categories',
  recurring: 'Recurring',
  wishlist: 'Wishlist',
  ledger: 'Money Tab',
  guide: 'Guides',
  command: 'Jump to',
};

const COMMANDS: { id: string; title: string; subtitle: string; screen: string; aliases: string[] }[] = [
  { id: 'home', title: 'Home', subtitle: 'Dashboard overview', screen: 'home', aliases: ['dashboard', 'home', 'overview'] },
  { id: 'activity', title: 'Activity', subtitle: 'All transactions', screen: 'activity', aliases: ['transactions', 'activity', 'history'] },
  { id: 'wallets', title: 'Wallets', subtitle: 'Accounts & balances', screen: 'wallets', aliases: ['accounts', 'wallets', 'banks'] },
  { id: 'plans', title: 'Plans', subtitle: 'Budget plans', screen: 'plan', aliases: ['budgets', 'plans', 'envelopes'] },
  { id: 'wishlist', title: 'Wishlist', subtitle: 'Things you want', screen: 'wishlist', aliases: ['wishlist', 'wishes', 'wants'] },
  { id: 'tab', title: 'Money Tab', subtitle: 'Who owes whom', screen: 'tab', aliases: ['tab', 'ledger', 'debts', 'owes'] },
  { id: 'recurring', title: 'Recurring', subtitle: 'Bills & income rules', screen: 'recurring', aliases: ['recurring', 'bills', 'subscriptions'] },
  { id: 'assistant', title: 'Ask Santim', subtitle: 'AI money chat', screen: 'assistant', aliases: ['ai', 'ask', 'assistant', 'chat', 'santim'] },
  { id: 'settings', title: 'Settings', subtitle: 'Preferences', screen: 'settings', aliases: ['settings', 'preferences'] },
];

function scoreText(q: string, ...fields: (string | null | undefined)[]): { score: number; matchFields: string[] } {
  const needle = q.toLowerCase().trim();
  if (!needle) return { score: 0, matchFields: [] };
  const matchFields: string[] = [];
  let score = 0;

  for (const raw of fields) {
    if (!raw) continue;
    const hay = raw.toLowerCase();
    if (hay === needle) {
      score += 100;
      matchFields.push(raw);
    } else if (hay.startsWith(needle)) {
      score += 70;
      matchFields.push(raw);
    } else if (hay.includes(needle)) {
      score += 40;
      matchFields.push(raw);
    } else {
      // Token overlap for multi-word queries.
      const tokens = needle.split(/\s+/).filter((t) => t.length >= 2);
      const hits = tokens.filter((t) => hay.includes(t)).length;
      if (hits > 0) {
        score += hits * 18;
        matchFields.push(raw);
      }
    }
  }
  return { score, matchFields };
}

function money(n: { toString(): string } | number | string | null | undefined): string | undefined {
  if (n == null) return undefined;
  return typeof n === 'string' ? n : n.toString();
}

/** Unified search across the user's money world. */
export async function search(userId: string, q: string, limit = 10) {
  const query = q.trim();
  if (query.length < 1) {
    return { q: query, groups: [] as SearchGroup[], total: 0 };
  }

  const take = Math.max(3, Math.min(limit, 30));
  const contains = { contains: query, mode: 'insensitive' as const };

  const [transactions, budgets, accounts, categories, recurring, wishlist, ledger] = await Promise.all([
    prisma.transaction.findMany({
      where: {
        userId,
        OR: [
          { note: contains },
          { payee: contains },
          { tags: { has: query } },
          { category: { name: contains } },
          { account: { name: contains } },
        ],
      },
      include: {
        category: { select: { id: true, name: true, icon: true, color: true } },
        account: { select: { id: true, name: true } },
      },
      orderBy: { date: 'desc' },
      take,
    }),
    prisma.budget.findMany({
      where: {
        userId,
        OR: [{ name: contains }, { note: contains }],
      },
      orderBy: { updatedAt: 'desc' },
      take,
    }),
    prisma.account.findMany({
      where: {
        userId,
        archived: false,
        OR: [{ name: contains }, { accountNumber: contains }],
      },
      orderBy: { name: 'asc' },
      take,
    }),
    prisma.category.findMany({
      where: {
        userId,
        archived: false,
        name: contains,
      },
      orderBy: { name: 'asc' },
      take,
    }),
    prisma.recurringRule.findMany({
      where: {
        userId,
        OR: [{ name: contains }, { payee: contains }, { note: contains }],
      },
      orderBy: { nextRun: 'asc' },
      take,
    }),
    prisma.wishlistItem.findMany({
      where: {
        userId,
        OR: [{ name: contains }, { note: contains }],
      },
      orderBy: { updatedAt: 'desc' },
      take,
    }),
    prisma.ledgerEntry.findMany({
      where: {
        userId,
        OR: [{ counterparty: contains }, { title: contains }, { note: contains }],
      },
      orderBy: { updatedAt: 'desc' },
      take,
    }),
  ]);

  const hits: SearchHit[] = [];

  for (const tx of transactions) {
    const { score, matchFields } = scoreText(
      query,
      tx.payee,
      tx.note,
      tx.category?.name,
      tx.account?.name,
      ...(tx.tags ?? []),
    );
    if (score <= 0) continue;
    hits.push({
      id: tx.id,
      type: 'transaction',
      title: tx.payee?.trim() || tx.note?.trim() || 'Transaction',
      subtitle: [tx.category?.name, tx.account?.name].filter(Boolean).join(' · ') || undefined,
      amount: money(tx.amount),
      currency: tx.currency,
      icon: tx.category?.icon,
      color: tx.category?.color,
      href: { screen: 'transaction', id: tx.id },
      score: score + 5, // slight boost — recent money moves are often what people want
      matchFields,
    });
  }

  for (const b of budgets) {
    const { score, matchFields } = scoreText(query, b.name, b.note);
    if (score <= 0) continue;
    hits.push({
      id: b.id,
      type: 'budget',
      title: b.name,
      subtitle: b.note ?? undefined,
      currency: b.currency,
      icon: b.icon,
      color: b.color,
      href: { screen: 'budget', id: b.id },
      score,
      matchFields,
    });
  }

  for (const a of accounts) {
    const { score, matchFields } = scoreText(query, a.name, a.accountNumber);
    if (score <= 0) continue;
    hits.push({
      id: a.id,
      type: 'account',
      title: a.name,
      subtitle: a.type.replace(/_/g, ' ').toLowerCase(),
      currency: a.currency,
      icon: a.icon,
      color: a.color,
      href: { screen: 'wallets' },
      score,
      matchFields,
    });
  }

  for (const c of categories) {
    const { score, matchFields } = scoreText(query, c.name);
    if (score <= 0) continue;
    hits.push({
      id: c.id,
      type: 'category',
      title: c.name,
      subtitle: c.kind === 'INCOME' ? 'Income' : 'Expense',
      icon: c.icon,
      color: c.color,
      href: { screen: 'activity', params: { categoryId: c.id } },
      score,
      matchFields,
    });
  }

  for (const r of recurring) {
    const { score, matchFields } = scoreText(query, r.name, r.payee, r.note);
    if (score <= 0) continue;
    hits.push({
      id: r.id,
      type: 'recurring',
      title: r.name,
      subtitle: r.payee ?? undefined,
      amount: money(r.amount),
      currency: r.currency,
      href: { screen: 'recurring', id: r.id },
      score,
      matchFields,
    });
  }

  for (const w of wishlist) {
    const { score, matchFields } = scoreText(query, w.name, w.note);
    if (score <= 0) continue;
    hits.push({
      id: w.id,
      type: 'wishlist',
      title: w.name,
      subtitle: w.status.toLowerCase(),
      icon: w.emoji,
      href: { screen: 'wishlist', id: w.id },
      score,
      matchFields,
    });
  }

  for (const e of ledger) {
    const { score, matchFields } = scoreText(query, e.counterparty, e.title, e.note);
    if (score <= 0) continue;
    hits.push({
      id: e.id,
      type: 'ledger',
      title: e.title?.trim() || e.counterparty,
      subtitle: e.counterparty,
      amount: money(e.totalAmount),
      currency: e.currency,
      href: { screen: 'tab', id: e.id, params: { e: e.id } },
      score,
      matchFields,
    });
  }

  for (const g of GUIDES) {
    const { score, matchFields } = scoreText(query, g.title, g.tagline, g.category, ...g.sections.map((s) => s.heading));
    if (score <= 0) continue;
    hits.push({
      id: g.id,
      type: 'guide',
      title: g.title,
      subtitle: g.tagline,
      icon: g.emoji,
      href: { screen: 'guide', id: g.id },
      score: score - 5,
      matchFields,
    });
  }

  const qLower = query.toLowerCase();
  for (const c of COMMANDS) {
    const aliasHit = c.aliases.some((a) => a.includes(qLower) || qLower.includes(a));
    const { score, matchFields } = scoreText(query, c.title, c.subtitle, ...c.aliases);
    if (!aliasHit && score <= 0) continue;
    hits.push({
      id: c.id,
      type: 'command',
      title: c.title,
      subtitle: c.subtitle,
      href: { screen: c.screen },
      score: Math.max(score, aliasHit ? 55 : 0),
      matchFields,
    });
  }

  hits.sort((a, b) => b.score - a.score);

  const order: SearchHitType[] = [
    'command',
    'transaction',
    'budget',
    'account',
    'ledger',
    'wishlist',
    'recurring',
    'category',
    'guide',
  ];

  const groups: SearchGroup[] = [];
  for (const type of order) {
    const items = hits.filter((h) => h.type === type).slice(0, take);
    if (items.length === 0) continue;
    groups.push({ type, label: LABELS[type], items });
  }

  return {
    q: query,
    groups,
    total: groups.reduce((n, g) => n + g.items.length, 0),
  };
}
