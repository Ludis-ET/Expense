/**
 * The figures a saving plan needs and a spending plan does not.
 *
 * A spending plan is asked "am I overspending?". A saving plan is asked "will I
 * get there, and when?" - which needs a finish line, a rate, and a sense of
 * whether the habit is holding. None of it touches money: every number here is
 * derived from the pot the ledger already reports.
 */
import { BudgetKind, BudgetState, BudgetType, Prisma, type Budget } from '../../core/prisma.js';

const ZERO = new Prisma.Decimal(0);
const DAY = 86_400_000;

export interface SavingFacts {
  /** The finish line, or null for an open-ended habit. */
  goalAmount: string | null;
  /** How much of the goal is in the pot, 0-100. Null without a goal. */
  pctOfGoal: number | null;
  /** Still to save before the goal is met. Null without a goal. */
  remainingToGoal: string | null;
  /** True once the pot has reached the finish line. */
  goalMet: boolean;

  /** RECURRING only: what this period asked for, and what it has had. */
  periodTarget: string | null;
  periodContributed: string | null;
  pctOfPeriod: number | null;

  /** Average per day since the first contribution. Drives the projection. */
  ratePerDay: string | null;
  /** When the goal lands at the current rate. Null if there is no goal, no
   *  rate, or the goal is already met. */
  projectedAt: string | null;
  /** Behind, on track, or ahead of `endDate`. Null without both dates. */
  pace: 'ahead' | 'on-track' | 'behind' | null;

  /** RECURRING only: consecutive periods whose target was met, most recent first. */
  streak: number;
  /** The last few periods as met/missed, oldest first - the card's dots. */
  recentPeriods: boolean[];
}

/** One contribution: a positive allocation. Give-backs are excluded. */
export interface Contribution {
  amount: Prisma.Decimal;
  date: Date;
  cycleIndex: number;
}

function pct(part: Prisma.Decimal, whole: Prisma.Decimal): number {
  if (whole.lte(0)) return 0;
  return Number(part.div(whole).mul(100).toFixed(1));
}

/**
 * Has this pot reached its finish line?
 *
 * The single completion test, and it applies to recurring plans too - a
 * recurring plan with a goal finishes. A plan with no goal never gets here,
 * which is exactly what makes it the open-ended habit.
 */
export function goalIsMet(budget: Pick<Budget, 'type' | 'goalAmount'>, pot: Prisma.Decimal): boolean {
  if (budget.type !== BudgetType.SAVING || budget.goalAmount === null) return false;
  return pot.gte(budget.goalAmount);
}

/**
 * The state a saving plan should be in, given its pot.
 *
 * Deliberately derived rather than stored as a separate flag, so the badge can
 * never disagree with the numbers beside it. CLOSED is a user decision and is
 * never overridden here.
 */
export function stateForSaving(
  budget: Pick<Budget, 'type' | 'goalAmount' | 'state'>,
  pot: Prisma.Decimal,
): BudgetState {
  if (budget.state === BudgetState.CLOSED) return BudgetState.CLOSED;
  if (budget.type !== BudgetType.SAVING) return BudgetState.ACTIVE;
  return goalIsMet(budget, pot) ? BudgetState.COMPLETED : BudgetState.ACTIVE;
}

/**
 * Contributions grouped into periods, newest period first.
 *
 * For a recurring plan the period is the cycle. A period counts as met when the
 * contributions dated inside it reach `plannedAmount`.
 */
function periodsMet(
  budget: Budget,
  contributions: Contribution[],
  limit: number,
): boolean[] {
  if (budget.kind !== BudgetKind.RECURRING || budget.plannedAmount.lte(0)) return [];

  const byCycle = new Map<number, Prisma.Decimal>();
  for (const c of contributions) {
    byCycle.set(c.cycleIndex, (byCycle.get(c.cycleIndex) ?? ZERO).add(c.amount));
  }

  // Walk back from the current cycle so a cycle with no contributions at all
  // still counts as a miss rather than being skipped.
  const out: boolean[] = [];
  for (let i = budget.cycleIndex; i >= 0 && out.length < limit; i--) {
    out.push((byCycle.get(i) ?? ZERO).gte(budget.plannedAmount));
  }
  return out.reverse(); // oldest first, which is how the dots read
}

/**
 * How many periods in a row, counting back from the one before the current.
 *
 * The current period is excluded: it is usually still in progress, and a streak
 * that drops to zero on the 1st of the month and climbs back on the 2nd would
 * be noise rather than information.
 */
function streakOf(met: boolean[]): number {
  let n = 0;
  // `met` is oldest-first, so walk from the end, skipping the current period.
  for (let i = met.length - 2; i >= 0; i--) {
    if (!met[i]) break;
    n += 1;
  }
  return n;
}

export function savingFacts(
  budget: Budget,
  pot: Prisma.Decimal,
  contributions: Contribution[],
  now = new Date(),
): SavingFacts | null {
  if (budget.type !== BudgetType.SAVING) return null;

  const goal = budget.goalAmount;
  const goalMet = goalIsMet(budget, pot);
  const remaining = goal ? Prisma.Decimal.max(ZERO, goal.sub(pot)) : null;

  // Rate is measured from the first contribution, not from the plan's start:
  // a plan created in January and first funded in June has been saving for the
  // months it was actually saving.
  const dated = [...contributions].sort((a, b) => a.date.getTime() - b.date.getTime());
  const first = dated[0];
  const totalIn = dated.reduce((s, c) => s.add(c.amount), ZERO);

  let ratePerDay: Prisma.Decimal | null = null;
  if (first && totalIn.gt(0)) {
    const days = Math.max(1, Math.ceil((now.getTime() - first.date.getTime()) / DAY));
    ratePerDay = totalIn.div(days);
  }

  let projectedAt: string | null = null;
  if (goal && !goalMet && remaining && ratePerDay && ratePerDay.gt(0)) {
    const daysLeft = Number(remaining.div(ratePerDay).toFixed(0));
    // A projection past a century is arithmetic, not information.
    if (Number.isFinite(daysLeft) && daysLeft >= 0 && daysLeft < 36_500) {
      projectedAt = new Date(now.getTime() + daysLeft * DAY).toISOString();
    }
  }

  let pace: SavingFacts['pace'] = null;
  if (budget.endDate && goal) {
    if (goalMet) pace = 'ahead';
    else if (!projectedAt) pace = 'behind';
    else {
      const slack = Date.parse(projectedAt) - budget.endDate.getTime();
      // A week either side of the deadline is "on track" - projections from a
      // handful of contributions are not precise enough to call it finer.
      pace = slack < -7 * DAY ? 'ahead' : slack > 7 * DAY ? 'behind' : 'on-track';
    }
  }

  const recurring = budget.kind === BudgetKind.RECURRING;
  const periodContributed = recurring
    ? contributions
        .filter((c) => c.cycleIndex === budget.cycleIndex)
        .reduce((s, c) => s.add(c.amount), ZERO)
    : null;

  const met = periodsMet(budget, contributions, 6);

  return {
    goalAmount: goal ? goal.toFixed(2) : null,
    pctOfGoal: goal ? Math.min(100, pct(pot, goal)) : null,
    remainingToGoal: remaining ? remaining.toFixed(2) : null,
    goalMet,

    periodTarget: recurring ? budget.plannedAmount.toFixed(2) : null,
    periodContributed: periodContributed ? periodContributed.toFixed(2) : null,
    pctOfPeriod:
      recurring && periodContributed
        ? Math.min(100, pct(periodContributed, budget.plannedAmount))
        : null,

    ratePerDay: ratePerDay ? ratePerDay.toFixed(2) : null,
    projectedAt,
    pace,

    streak: streakOf(met),
    recentPeriods: met,
  };
}
