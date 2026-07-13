import { TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import * as currency from '../../core/currency.service.js';
import * as analytics from '../analytics/analytics.service.js';
import * as budgets from '../budgets/budgets.service.js';
import { monthRange } from '../budgets/budgets.service.js';
import * as wishlist from '../wishlist/wishlist.service.js';
import { spendableFor } from '../spend-locks/spend-locks.service.js';
import { GUIDES } from './guides.content.js';

export type SuggestionTone = 'tip' | 'success' | 'warning';

export interface Suggestion {
  id: string;
  title: string;
  body: string;
  tone: SuggestionTone;
  guideId?: string;
  href?: string;
  cta?: string;
}

/** A snapshot of the user's finances, used to tailor which guides to surface. */
async function snapshot(user: AuthUser) {
  const cur = await currency.resolveCurrency(user.id);
  const { start, end } = monthRange();

  const [monthRows, txCount, spendable, goalsActive, savingsPlans, budgetList, wishDigest, unnecessary] =
    await Promise.all([
      prisma.transaction.groupBy({
        by: ['kind'],
        where: { userId: user.id, currency: cur, date: { gte: start, lt: end }, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] } },
        _sum: { amount: true },
      }),
      prisma.transaction.count({ where: { userId: user.id } }),
      spendableFor(user.id, cur),
      prisma.savingsGoal.count({ where: { userId: user.id, achievedAt: null } }),
      prisma.recurringRule.count({
        where: { userId: user.id, active: true, OR: [{ goalId: { not: null } }, { wishlistItemId: { not: null } }] },
      }),
      budgets.list(user),
      wishlist.dashboard(user, cur),
      analytics.unnecessary(user, undefined, cur),
    ]);

  const income = Number(monthRows.find((r) => r.kind === TxKind.INCOME)?._sum.amount ?? 0);
  const expense = Number(monthRows.find((r) => r.kind === TxKind.EXPENSE)?._sum.amount ?? 0);
  const savingsRate = income > 0 ? Math.round(((income - expense) / income) * 100) : null;

  return {
    currency: cur,
    txCount,
    savingsRate,
    lockCount: spendable.lockCount,
    goalsActive,
    savingsPlans,
    budgetCount: budgetList.items.length,
    budgetsAtRisk: budgetList.items.filter((b) => b.status !== 'ok').length,
    activeWants: wishDigest.activeCount,
    affordableWants: wishDigest.affordableCount,
    unnecessary: Number(unnecessary.total),
  };
}

/** Personalized, prioritized guidance that links a lesson to a place to act. */
export async function forYou(user: AuthUser): Promise<Suggestion[]> {
  const s = await snapshot(user);
  const out: { s: Suggestion; priority: number }[] = [];
  const add = (priority: number, sug: Suggestion) => out.push({ priority, s: sug });

  if (s.txCount < 5) {
    add(100, {
      id: 'start-logging',
      title: 'Log a full week of spending',
      body: 'The habit that makes everything else work: capture every birr in and out for seven days. Press N anywhere to add one fast.',
      tone: 'tip',
      guideId: 'getting-started',
      href: '/transactions',
      cta: 'Add a transaction',
    });
  }

  if (s.lockCount === 0) {
    add(90, {
      id: 'set-floor',
      title: 'Protect yourself with a safety floor',
      body: 'You have no spend locks yet. A safety-floor lock stops everyday expenses from eating into money you cannot afford to lose.',
      tone: 'tip',
      guideId: 'emergency-fund',
      href: '/locks',
      cta: 'Set a lock',
    });
  }

  if (s.savingsRate !== null && s.savingsRate < 20) {
    add(85, {
      id: 'savings-rate',
      title: `Your savings rate is ${s.savingsRate}% this month`,
      body: 'Below the 20% many aim for. The 50/30/20 rule is a simple way to rebalance needs, wants, and savings — and paying yourself first makes it stick.',
      tone: 'warning',
      guideId: '50-30-20',
      href: '/budgets',
      cta: 'Review budgets',
    });
  } else if (s.savingsRate !== null && s.savingsRate >= 20) {
    add(40, {
      id: 'savings-rate-good',
      title: `Strong ${s.savingsRate}% savings rate 🎉`,
      body: 'You are keeping a healthy share of your income. Consider automating it so it keeps happening even on busy months.',
      tone: 'success',
      guideId: 'automate-saving',
      href: '/recurring',
      cta: 'Automate saving',
    });
  }

  if (s.unnecessary > 0) {
    add(70, {
      id: 'unnecessary',
      title: 'Trim impulse spending',
      body: `You've flagged ${s.unnecessary.toFixed(2)} ${s.currency} as unnecessary this month. Try the 24-hour rule and park temptations on your wishlist instead.`,
      tone: 'tip',
      guideId: 'curb-impulse',
      href: '/analytics',
      cta: 'See where it goes',
    });
  }

  if (s.activeWants > 0 && s.goalsActive === 0) {
    add(65, {
      id: 'promote-want',
      title: 'Turn a want into a goal',
      body: 'You have wishlist items but no savings goals. Promoting a want gives it a plan, a deadline, and optional auto-saving.',
      tone: 'tip',
      guideId: 'goals-vs-wants',
      href: '/wishlist',
      cta: 'Open wishlist',
    });
  }

  if (s.goalsActive > 0 && s.savingsPlans === 0) {
    add(60, {
      id: 'automate',
      title: 'Automate your saving',
      body: 'Your goals rely on remembering to contribute. An auto-save plan moves money for you every period — and shows a projected finish date.',
      tone: 'tip',
      guideId: 'automate-saving',
      href: '/recurring',
      cta: 'Create a plan',
    });
  }

  if (s.affordableWants > 0) {
    add(55, {
      id: 'affordable',
      title: `You can afford ${s.affordableWants} want${s.affordableWants === 1 ? '' : 's'} now`,
      body: 'You have saved enough (after locks) to buy them guilt-free. Or keep the momentum and redirect the money to a goal.',
      tone: 'success',
      guideId: 'goals-vs-wants',
      href: '/wishlist',
      cta: 'Review wishlist',
    });
  }

  if (s.budgetCount === 0) {
    add(50, {
      id: 'first-budget',
      title: 'Set your first budget',
      body: 'Budgets cap a category and warn you before you overspend. Start with the one category that always surprises you.',
      tone: 'tip',
      guideId: 'budget-basics',
      href: '/budgets',
      cta: 'Add a budget',
    });
  } else if (s.budgetsAtRisk > 0) {
    add(75, {
      id: 'budget-risk',
      title: `${s.budgetsAtRisk} budget${s.budgetsAtRisk === 1 ? '' : 's'} at risk`,
      body: 'One or more categories are near or over their limit. Rebalance now while there is still month left.',
      tone: 'warning',
      guideId: 'budget-basics',
      href: '/budgets',
      cta: 'Rebalance',
    });
  }

  return out.sort((a, b) => b.priority - a.priority).slice(0, 6).map((x) => x.s);
}

export async function overview(user: AuthUser) {
  const suggestions = await forYou(user);
  return { guides: GUIDES, suggestions };
}
