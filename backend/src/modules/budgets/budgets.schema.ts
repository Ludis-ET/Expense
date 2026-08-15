import { z } from 'zod';
import {
  AdjustmentDial,
  BudgetKind,
  BudgetState,
  BudgetType,
  RecurrenceUnit,
} from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

/**
 * The finish line a saving pot accumulates toward.
 *
 * Explicitly nullable, because null is meaningful rather than missing: it is
 * the open-ended habit that runs forever.
 */
const goalAmount = money.nullish();

/**
 * Users cannot create the built-in UNPLANNED plan - it is provisioned once per
 * account - so only the two authorable kinds are accepted here.
 */
const authorableKind = z.enum([BudgetKind.ONE_TIME, BudgetKind.RECURRING]);

/** "every N <unit>" - 6 hours, 3 days, 2 weeks, a quarter... */
const recurrenceInterval = z.coerce.number().int().min(1).max(365);

export const createBudgetSchema = z
  .object({
    name: z.string().trim().min(1, 'Give the plan a name').max(80),
    /** Optional - only pre-selects itself when you spend from the plan. */
    categoryId: z.string().min(1).nullish(),
    kind: authorableKind.default(BudgetKind.ONE_TIME),
    /** Spending ceiling or savings goal. Defaults to what plans have always been. */
    type: z.nativeEnum(BudgetType).default(BudgetType.SPENDING),
    recurrenceUnit: z.nativeEnum(RecurrenceUnit).nullish(),
    recurrenceInterval: recurrenceInterval.default(1),
    plannedAmount: money,
    goalAmount,
    currency: z.string().length(3).default('ETB'),
    icon: z.string().max(40).nullish(),
    color: z.string().max(20).nullish(),
    note: z.string().max(500).nullish(),
    alertThreshold: z.coerce.number().int().min(1).max(100).default(80),
    /** When the plan begins. Defaults to now, but the user picks. */
    startsAt: z.coerce.date().optional(),
    endDate: z.coerce.date().nullish(),
  })
  .refine((d) => d.kind !== BudgetKind.RECURRING || !!d.recurrenceUnit, {
    message: 'Pick how often this plan repeats',
    path: ['recurrenceUnit'],
  })
  .refine((d) => !(d.startsAt && d.endDate) || d.endDate >= d.startsAt, {
    message: 'End date must be on or after the start date',
    path: ['endDate'],
  });

export const updateBudgetSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  categoryId: z.string().min(1).nullish(),
  kind: authorableKind.optional(),
  recurrenceUnit: z.nativeEnum(RecurrenceUnit).nullish(),
  recurrenceInterval: recurrenceInterval.optional(),
  plannedAmount: money.optional(),
  goalAmount,
  icon: z.string().max(40).nullish(),
  color: z.string().max(20).nullish(),
  note: z.string().max(500).nullish(),
  alertThreshold: z.coerce.number().int().min(1).max(100).optional(),
  startsAt: z.coerce.date().optional(),
  endDate: z.coerce.date().nullish(),
});

/**
 * Turning a plan from one kind into the other.
 *
 * `type` is deliberately required rather than a toggle: the client states where
 * it wants to end up, so a retry is idempotent instead of flipping it back.
 *
 * The rest is the same set of questions the create form asks, because that is
 * genuinely what conversion needs. A monthly grocery ceiling makes a nonsense
 * savings goal, so the target is asked for rather than inherited; and a saving
 * plan has no cadence, so becoming a spending plan needs one.
 */
export const convertBudgetSchema = z
  .object({
    type: z.nativeEnum(BudgetType),
    /** Required when converting to SPENDING - a plan with no ceiling has nothing to reset against. */
    plannedAmount: money.optional(),
    /** The finish line. Omit or null for an open-ended saving habit. */
    goalAmount,
    kind: authorableKind.optional(),
    recurrenceUnit: z.nativeEnum(RecurrenceUnit).nullish(),
    recurrenceInterval: recurrenceInterval.optional(),
    endDate: z.coerce.date().nullish(),
    /** Give the surplus back rather than opening the plan already over its line. */
    releaseSurplusTo: z.string().min(1).nullish(),
    reason: z.string().max(200).nullish(),
  })
  .refine((d) => d.type !== BudgetType.SPENDING || d.plannedAmount !== undefined, {
    message: 'A spending plan needs a planned amount',
    path: ['plannedAmount'],
  })
  .refine((d) => d.kind !== BudgetKind.RECURRING || !!d.recurrenceUnit, {
    message: 'Pick how often this plan repeats',
    path: ['recurrenceUnit'],
  });

/**
 * The client's own id for this operation. A queued write whose reply was lost
 * gets retried; without this the retry sets the money aside a second time.
 */
const clientOpId = z.string().min(1).max(80).nullish();

export const fundBudgetSchema = z.object({
  accountId: z.string().min(1, 'Pick an account'),
  amount: money,
  date: z.coerce.date().optional(),
  note: z.string().max(200).nullish(),
  clientOpId,
});

/** Move money straight from one plan to another, without a round trip through a wallet. */
export const movePlanMoneySchema = z.object({
  toBudgetId: z.string().min(1, 'Pick where the money is going'),
  amount: money,
  /** Raise the receiving plan if the money would not fit inside it. */
  raiseTarget: z.boolean().default(false),
  date: z.coerce.date().optional(),
  clientOpId,
});

/**
 * Move a plan's reservation from one wallet to another. The plan is untouched -
 * this is for when the cash itself has moved and the envelope has to follow.
 */
export const moveReservationSchema = z.object({
  fromAccountId: z.string().min(1, 'Pick the wallet holding it now'),
  toAccountId: z.string().min(1, 'Pick where it should be held'),
  amount: money,
  date: z.coerce.date().optional(),
  clientOpId,
});

/**
 * Raise or cut one of a plan's amounts. The direction is explicit rather than a
 * signed number so a stray minus sign can never turn a top-up into a cut.
 *
 * `dial` says *which* amount. A recurring saving plan has two, and they pull in
 * opposite directions - raising the monthly contribution finishes it sooner,
 * raising the goal finishes it later - so leaving it implicit would be the
 * obvious way to get this wrong. Defaults to PLANNED, which is every adjustment
 * that existed before saving plans did.
 */
export const adjustBudgetSchema = z.object({
  direction: z.enum(['ADD', 'DEDUCT']),
  dial: z.nativeEnum(AdjustmentDial).default(AdjustmentDial.PLANNED),
  amount: money,
  reason: z.string().trim().max(200).nullish(),
  date: z.coerce.date().optional(),
  clientOpId,
});

export const releaseBudgetSchema = z.object({
  /** Defaults to the account with the largest share of the pot. */
  accountId: z.string().min(1).optional(),
  amount: money,
  date: z.coerce.date().optional(),
  note: z.string().max(200).nullish(),
  clientOpId,
});

export const listBudgetsQuery = z.object({
  state: z.nativeEnum(BudgetState).optional(),
  currency: z.string().length(3).optional(),
});

export const budgetSourcesQuery = z.object({
  currency: z.string().length(3).optional(),
});

export const budgetIdParam = z.object({ id: z.string().min(1) });

export type CreateBudgetInput = z.infer<typeof createBudgetSchema>;
export type UpdateBudgetInput = z.infer<typeof updateBudgetSchema>;
export type ConvertBudgetInput = z.infer<typeof convertBudgetSchema>;
export type FundBudgetInput = z.infer<typeof fundBudgetSchema>;
export type AdjustBudgetInput = z.infer<typeof adjustBudgetSchema>;
export type ReleaseBudgetInput = z.infer<typeof releaseBudgetSchema>;
export type MovePlanMoneyInput = z.infer<typeof movePlanMoneySchema>;
export type MoveReservationInput = z.infer<typeof moveReservationSchema>;
export type ListBudgetsQuery = z.infer<typeof listBudgetsQuery>;
