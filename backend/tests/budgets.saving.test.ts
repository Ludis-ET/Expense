import { describe, expect, it } from 'vitest';
import { BudgetKind, BudgetState, BudgetType, Prisma } from '../src/core/prisma.js';
import {
  goalIsMet,
  savingFacts,
  stateForSaving,
  type Contribution,
} from '../src/modules/budgets/budgets.saving.js';

const d = (n: number | string) => new Prisma.Decimal(n);
const at = (iso: string) => new Date(iso);
const NOW = at('2026-08-15T00:00:00Z');

/** Only the fields the saving maths reads. */
function plan(over: Partial<Record<string, unknown>> = {}) {
  return {
    id: 'b1',
    name: 'Kenya trip',
    type: BudgetType.SAVING,
    kind: BudgetKind.ONE_TIME,
    state: BudgetState.ACTIVE,
    plannedAmount: d(40000),
    goalAmount: d(40000),
    cycleIndex: 0,
    endDate: null,
    ...over,
  } as never;
}

const contrib = (amount: number, iso: string, cycleIndex = 0): Contribution => ({
  amount: d(amount),
  date: at(iso),
  cycleIndex,
});

describe('goalIsMet', () => {
  it('is false for a spending plan whatever the pot holds', () => {
    expect(goalIsMet({ type: BudgetType.SPENDING, goalAmount: d(100) }, d(500))).toBe(false);
  });

  it('is false when there is no finish line', () => {
    // The open-ended habit. It never completes, which is the point of it.
    expect(goalIsMet({ type: BudgetType.SAVING, goalAmount: null }, d(999_999))).toBe(false);
  });

  it('is true at exactly the goal, not only past it', () => {
    expect(goalIsMet({ type: BudgetType.SAVING, goalAmount: d(40000) }, d(40000))).toBe(true);
    expect(goalIsMet({ type: BudgetType.SAVING, goalAmount: d(40000) }, d(39999.99))).toBe(false);
  });
});

describe('stateForSaving', () => {
  const saving = { type: BudgetType.SAVING, goalAmount: d(1000), state: BudgetState.ACTIVE };

  it('completes when the pot reaches the goal', () => {
    expect(stateForSaving(saving, d(1000))).toBe(BudgetState.COMPLETED);
  });

  it('re-opens when the goal is raised above the pot', () => {
    // The documented way to un-complete a plan: raise the target. The state is
    // derived, so no separate re-open button can disagree with the numbers.
    const raised = { ...saving, goalAmount: d(1500) };
    expect(stateForSaving(raised, d(1000))).toBe(BudgetState.ACTIVE);
  });

  it('never overrides a plan the user closed', () => {
    const closed = { ...saving, state: BudgetState.CLOSED };
    expect(stateForSaving(closed, d(5000))).toBe(BudgetState.CLOSED);
  });

  it('leaves spending plans alone', () => {
    expect(stateForSaving({ ...saving, type: BudgetType.SPENDING }, d(9999))).toBe(
      BudgetState.ACTIVE,
    );
  });
});

describe('savingFacts', () => {
  it('returns nothing for a spending plan', () => {
    expect(savingFacts(plan({ type: BudgetType.SPENDING }), d(100), [], NOW)).toBeNull();
  });

  it('reports progress toward the goal', () => {
    const f = savingFacts(plan(), d(27500), [contrib(27500, '2026-06-15T00:00:00Z')], NOW)!;
    expect(f.pctOfGoal).toBeCloseTo(68.8, 1);
    expect(f.remainingToGoal).toBe('12500.00');
    expect(f.goalMet).toBe(false);
  });

  it('has no percentage without a finish line', () => {
    const f = savingFacts(
      plan({ goalAmount: null, kind: BudgetKind.RECURRING, plannedAmount: d(2000) }),
      d(86000),
      [contrib(2000, '2026-08-01T00:00:00Z')],
      NOW,
    )!;
    expect(f.pctOfGoal).toBeNull();
    expect(f.remainingToGoal).toBeNull();
    expect(f.goalMet).toBe(false);
  });

  it('projects a finish date from the rate since the first contribution', () => {
    // 10,000 over the 20 days since the first contribution = 500/day.
    // 30,000 still to go, so roughly 60 more days.
    const f = savingFacts(
      plan(),
      d(10000),
      [contrib(5000, '2026-07-26T00:00:00Z'), contrib(5000, '2026-08-10T00:00:00Z')],
      NOW,
    )!;
    expect(f.ratePerDay).toBe('500.00');
    const projected = new Date(f.projectedAt!);
    const daysOut = Math.round((projected.getTime() - NOW.getTime()) / 86_400_000);
    expect(daysOut).toBe(60);
  });

  it('does not project once the goal is met', () => {
    const f = savingFacts(plan(), d(40000), [contrib(40000, '2026-07-01T00:00:00Z')], NOW)!;
    expect(f.goalMet).toBe(true);
    expect(f.projectedAt).toBeNull();
  });

  it('does not project with no contributions to measure', () => {
    const f = savingFacts(plan(), d(0), [], NOW)!;
    expect(f.ratePerDay).toBeNull();
    expect(f.projectedAt).toBeNull();
  });

  describe('pace against a deadline', () => {
    const withDeadline = (iso: string) => plan({ endDate: at(iso) });
    // 500/day, 30,000 to go -> lands about 60 days out, ~14 October.
    const rows = [contrib(5000, '2026-07-26T00:00:00Z'), contrib(5000, '2026-08-10T00:00:00Z')];

    it('is ahead when the projection lands well before the deadline', () => {
      expect(savingFacts(withDeadline('2027-01-01T00:00:00Z'), d(10000), rows, NOW)!.pace).toBe(
        'ahead',
      );
    });

    it('is behind when it lands well after', () => {
      expect(savingFacts(withDeadline('2026-09-01T00:00:00Z'), d(10000), rows, NOW)!.pace).toBe(
        'behind',
      );
    });

    it('is on track within a week either side', () => {
      expect(savingFacts(withDeadline('2026-10-14T00:00:00Z'), d(10000), rows, NOW)!.pace).toBe(
        'on-track',
      );
    });

    it('is behind when there is no rate at all', () => {
      expect(savingFacts(withDeadline('2026-09-01T00:00:00Z'), d(0), [], NOW)!.pace).toBe('behind');
    });
  });

  describe('recurring contributions', () => {
    const habit = (cycleIndex: number) =>
      plan({
        kind: BudgetKind.RECURRING,
        plannedAmount: d(2000),
        goalAmount: null,
        cycleIndex,
      });

    it('measures this period against its target', () => {
      const f = savingFacts(
        habit(3),
        d(8000),
        [contrib(2000, '2026-05-02T00:00:00Z', 0), contrib(1400, '2026-08-02T00:00:00Z', 3)],
        NOW,
      )!;
      expect(f.periodTarget).toBe('2000.00');
      expect(f.periodContributed).toBe('1400.00');
      expect(f.pctOfPeriod).toBe(70);
    });

    it('counts a streak of met periods, excluding the one in progress', () => {
      // Cycles 0-2 met, cycle 3 (current) is short. The streak is the three
      // finished periods; a partial current month must not zero it.
      const rows = [
        contrib(2000, '2026-05-02T00:00:00Z', 0),
        contrib(2000, '2026-06-02T00:00:00Z', 1),
        contrib(2000, '2026-07-02T00:00:00Z', 2),
        contrib(500, '2026-08-02T00:00:00Z', 3),
      ];
      const f = savingFacts(habit(3), d(6500), rows, NOW)!;
      expect(f.streak).toBe(3);
      expect(f.recentPeriods).toEqual([true, true, true, false]);
    });

    it('breaks the streak on a missed period', () => {
      const rows = [
        contrib(2000, '2026-05-02T00:00:00Z', 0),
        // cycle 1 missed entirely
        contrib(2000, '2026-07-02T00:00:00Z', 2),
        contrib(2000, '2026-08-02T00:00:00Z', 3),
      ];
      const f = savingFacts(habit(3), d(6000), rows, NOW)!;
      expect(f.streak).toBe(1);
      expect(f.recentPeriods).toEqual([true, false, true, true]);
    });

    it('has no period figures on a one-time plan', () => {
      const f = savingFacts(plan(), d(100), [contrib(100, '2026-08-01T00:00:00Z')], NOW)!;
      expect(f.periodTarget).toBeNull();
      expect(f.pctOfPeriod).toBeNull();
      expect(f.recentPeriods).toEqual([]);
      expect(f.streak).toBe(0);
    });
  });

  it('a recurring plan can still have a finish line', () => {
    // The case that made goalAmount a separate column: "5,000 a month until
    // 120,000". Both numbers are live at once and neither is implied.
    const f = savingFacts(
      plan({ kind: BudgetKind.RECURRING, plannedAmount: d(5000), goalAmount: d(120000), cycleIndex: 5 }),
      d(30000),
      [contrib(2800, '2026-08-03T00:00:00Z', 5)],
      NOW,
    )!;
    expect(f.pctOfGoal).toBe(25);
    expect(f.periodTarget).toBe('5000.00');
    expect(f.periodContributed).toBe('2800.00');
    expect(f.goalMet).toBe(false);
  });
});
