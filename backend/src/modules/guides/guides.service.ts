import { TxKind } from "../../core/prisma.js";
import { prisma } from "../../core/db.js";
import type { AuthUser } from "../../core/context.js";
import * as currency from "../../core/currency.service.js";
import * as analytics from "../analytics/analytics.service.js";
import * as budgets from "../budgets/budgets.service.js";
import { monthRange } from "../budgets/budgets.service.js";
import * as wishlist from "../wishlist/wishlist.service.js";
import { GUIDES } from "./guides.content.js";

export type SuggestionTone = "tip" | "success" | "warning";

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

  const [
    monthRows,
    txCount,
    unplannedWants,
    budgetList,
    wishDigest,
    unnecessary,
  ] = await Promise.all([
    prisma.transaction.groupBy({
      by: ["kind"],
      where: {
        userId: user.id,
        currency: cur,
        date: { gte: start, lt: end },
        kind: { in: [TxKind.INCOME, TxKind.EXPENSE] },
      },
      _sum: { amount: true },
    }),
    prisma.transaction.count({ where: { userId: user.id } }),
    prisma.wishlistItem.count({
      where: { userId: user.id, status: 'WANTING' },
    }),
    budgets.list(user),
    wishlist.dashboard(user),
    analytics.unnecessary(user, undefined, cur),
  ]);

  const income = Number(
    monthRows.find((r) => r.kind === TxKind.INCOME)?._sum.amount ?? 0,
  );
  const expense = Number(
    monthRows.find((r) => r.kind === TxKind.EXPENSE)?._sum.amount ?? 0,
  );
  const savingsRate =
    income > 0 ? Math.round(((income - expense) / income) * 100) : null;

  return {
    currency: cur,
    txCount,
    savingsRate,
    unplannedWants,
    budgetCount: budgetList.items.length,
    budgetsUnfunded: budgetList.items.filter(
      (b) => b.state === "ACTIVE" && Number(b.fundedAmount) <= 0,
    ).length,
    budgetsRunningLow: budgetList.items.filter(
      (b) => b.health === "low" || b.health === "drained",
    ).length,
    activeWants: wishDigest.activeCount,
    plannedWants: wishDigest.plannedCount,
    unnecessary: Number(unnecessary.total),
  };
}

/** Personalized, prioritized guidance that links a lesson to a place to act. */
export async function forYou(user: AuthUser): Promise<Suggestion[]> {
  const s = await snapshot(user);
  const out: { s: Suggestion; priority: number }[] = [];
  const add = (priority: number, sug: Suggestion) =>
    out.push({ priority, s: sug });

  if (s.txCount < 5) {
    add(100, {
      id: "start-logging",
      title: "Log a full week of spending",
      body: "The habit that makes everything else work: capture every birr in and out for seven days. Press N anywhere to add one fast.",
      tone: "tip",
      guideId: "getting-started",
      href: "/transactions",
      cta: "Add a transaction",
    });
  }

  if (s.savingsRate !== null && s.savingsRate < 20) {
    add(85, {
      id: "savings-rate",
      title: `Your savings rate is ${s.savingsRate}% this month`,
      body: "Below the 20% many aim for. The 50/30/20 rule is a simple way to rebalance needs, wants, and savings   and paying yourself first makes it stick.",
      tone: "warning",
      guideId: "50-30-20",
      href: "/budgets",
      cta: "Review budgets",
    });
  } else if (s.savingsRate !== null && s.savingsRate >= 20) {
    add(40, {
      id: "savings-rate-good",
      title: `Strong ${s.savingsRate}% savings rate 🎉`,
      body: "You are keeping a healthy share of your income. Consider automating it so it keeps happening even on busy months.",
      tone: "success",
      guideId: "automate-saving",
      href: "/recurring",
      cta: "Automate saving",
    });
  }

  if (s.unnecessary > 0) {
    add(70, {
      id: "unnecessary",
      title: "Trim impulse spending",
      body: `You've flagged ${s.unnecessary.toFixed(2)} ${s.currency} as unnecessary this month. Try the 24-hour rule and park temptations on your wishlist instead.`,
      tone: "tip",
      guideId: "curb-impulse",
      href: "/analytics",
      cta: "See where it goes",
    });
  }

  if (s.unplannedWants > 0) {
    add(60, {
      id: "plan-a-want",
      title: `${s.unplannedWants} want${s.unplannedWants === 1 ? " has" : "s have"} no plan yet`,
      body: "A want is only a wish until money is set aside for it. Planning one turns it into a budget plan you can fill a little at a time.",
      tone: "tip",
      guideId: "budget-basics",
      href: "/budgets?tab=wishlist",
      cta: "Plan a want",
    });
  }

  if (s.plannedWants > 0) {
    add(55, {
      id: "planned-wants",
      title: `${s.plannedWants} want${s.plannedWants === 1 ? " is" : "s are"} being saved for`,
      body: "Top the plans up whenever money comes in, and buy guilt-free once they are full.",
      tone: "success",
      guideId: "budget-basics",
      href: "/budgets?tab=wishlist",
      cta: "Review wishlist",
    });
  }

  if (s.budgetCount === 0) {
    add(50, {
      id: "first-budget",
      title: "Create your first budget plan",
      body: "A plan is an envelope you fill from your accounts. Once money is in it, it drops out of your available balance and can only be spent on that plan - the simplest way to ring-fence rent, fees or an emergency buffer.",
      tone: "tip",
      guideId: "budget-basics",
      href: "/budgets",
      cta: "Add a plan",
    });
  } else if (s.budgetsUnfunded > 0) {
    add(68, {
      id: "budget-unfunded",
      title: `${s.budgetsUnfunded} plan${s.budgetsUnfunded === 1 ? " is" : "s are"} still empty`,
      body: "A plan does nothing until you fill it. Move money in from an account so it is reserved before you spend it.",
      tone: "tip",
      guideId: "budget-basics",
      href: "/budgets",
      cta: "Fill a plan",
    });
  } else if (s.budgetsRunningLow > 0) {
    add(75, {
      id: "budget-risk",
      title: `${s.budgetsRunningLow} plan${s.budgetsRunningLow === 1 ? " is" : "s are"} running low`,
      body: "One or more plans are close to empty. Top them up, or ease off until the next cycle.",
      tone: "warning",
      guideId: "budget-basics",
      href: "/budgets",
      cta: "Rebalance",
    });
  }

  return out
    .sort((a, b) => b.priority - a.priority)
    .slice(0, 6)
    .map((x) => x.s);
}

export async function overview(user: AuthUser) {
  const suggestions = await forYou(user);
  return { guides: GUIDES, suggestions };
}
