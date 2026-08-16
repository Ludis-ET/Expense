export type TxKind = 'INCOME' | 'EXPENSE' | 'TRANSFER';
export type CategoryKind = 'INCOME' | 'EXPENSE';
export type AccountType = 'CASH' | 'BANK' | 'MOBILE_MONEY' | 'CARD' | 'OTHER';
export type Frequency = 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
export type LedgerKind = 'LENT' | 'BORROWED' | 'EXPECTED_IN' | 'EXPECTED_OUT';
export type LedgerStatus = 'OPEN' | 'SETTLED' | 'CANCELLED';

export interface User {
  id: string;
  name: string;
  email: string;
  locale?: string;
  calendar?: 'gregorian' | 'ethiopian';
  currency: string;
  firstDayOfWeek: number;
  avatarId?: string;
  bannerId?: string;
  /** Wallet that holds physical cash (ATM withdrawals transfer into it). */
  cashAccountId?: string | null;
}

export interface AuthResponse {
  user: { id: string; email: string };
  accessToken: string;
  refreshToken: string;
}

export interface Account {
  id: string;
  name: string;
  type: AccountType;
  currency: string;
  openingBalance: string;
  /** Available: real money minus what budget plans have reserved. */
  balance: string;
  /** Money physically in the account. */
  realBalance: string;
  /** Reserved by budget plans. */
  lockedAmount: string;
  icon?: string | null;
  color?: string | null;
  isDefault: boolean;
  archived: boolean;
  isShared?: boolean;
  householdId?: string | null;
  /** What the bank itself last said this wallet holds, read out of an SMS. */
  reportedBalance?: string | null;
  reportedAt?: string | null;
  /** Ours minus the bank's. Positive means spending we never recorded. */
  drift?: string | null;
}

/** What one wallet is holding, and for which plan. */
export interface WalletReservation {
  plan: { id: string; name: string; icon: string | null; color: string | null; currency: string; state: BudgetState };
  amount: string;
}

export interface Category {
  id: string;
  name: string;
  kind: CategoryKind;
  icon: string;
  color: string;
  isDefault: boolean;
  archived: boolean;
  transactionCount?: number;
}

export interface Transaction {
  id: string;
  kind: TxKind;
  amount: string;
  currency: string;
  date: string;
  accountId: string;
  account?: { id: string; name: string; type?: AccountType };
  transferAccountId?: string | null;
  transferAccount?: { id: string; name: string } | null;
  categoryId?: string | null;
  category?: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  /** Set when the expense was paid out of a budget plan's pot. */
  budgetId?: string | null;
  budget?: { id: string; name: string; icon?: string | null; color?: string | null; currency: string } | null;
  budgetCycle?: number | null;
  /**
   * The funding account whose reservation this plan expense freed. Differs from
   * `accountId` when the plan was filled from one wallet and paid from another.
   */
  budgetSourceAccountId?: string | null;
  budgetSourceAccount?: { id: string; name: string; type?: AccountType } | null;
  /**
   * True when the wallet that paid is not the wallet holding the plan's money -
   * it fronted the cash, and the plan's own wallet freed the reservation.
   */
  fronted?: boolean;
  /** What arrived, when a transfer crossed a currency. */
  transferAmount?: string | null;
  transferRate?: string | null;
  note?: string | null;
  payee?: string | null;
  tags: string[];
  recurringRuleId?: string | null;
  /** Client-only: set on transactions still queued in the offline outbox. */
  pending?: 'pending' | 'syncing' | 'error';
}

/** Where the shortfall comes from when a plan cannot cover a spend. */
export type SpendCover =
  | { from: 'BUDGET'; budgetId: string }
  | { from: 'ACCOUNT'; accountId: string };

/**
 * The structured half of a refusal, so the UI can offer the fix rather than
 * only printing the sentence.
 */
export interface ShortfallDetails {
  reason: 'PLAN_SHORT' | 'ACCOUNT_SHORT';
  shortfall: string;
  currency: string;
  budgetId?: string;
  accountId?: string;
}

export interface TransactionPage {
  items: Transaction[];
  total: number;
  page: number;
  pageSize: number;
}

export interface RecurringRule {
  id: string;
  name: string;
  kind: TxKind;
  amount: string;
  currency: string;
  accountId: string;
  account?: { id: string; name: string };
  categoryId?: string | null;
  category?: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  /** Required for EXPENSE — ACTIVE SPENDING plan the rule draws from. */
  budgetId?: string | null;
  budget?: { id: string; name: string } | null;
  payee?: string | null;
  note?: string | null;
  frequency: Frequency;
  interval: number;
  dayOfMonth?: number | null;
  nextRun: string;
  endDate?: string | null;
  autoPost: boolean;
  active: boolean;
  postedCount: number;
}

/** The step a recurring plan advances by; paired with an interval. */
export type RecurrenceUnit = 'HOUR' | 'DAY' | 'WEEK' | 'MONTH' | 'QUARTER' | 'YEAR';
export type BudgetKind = 'ONE_TIME' | 'RECURRING' | 'UNPLANNED';
export type BudgetState = 'ACTIVE' | 'CLOSED';
export type BudgetHealth =
  | 'unplanned'
  | 'scheduled'
  | 'empty'
  | 'partly-funded'
  | 'ready'
  | 'spending'
  | 'low'
  | 'drained'
  | 'closed';

export type BudgetCategory = Pick<Category, 'id' | 'name' | 'icon' | 'color' | 'kind'>;
export type BudgetAccount = Pick<Account, 'id' | 'name' | 'type' | 'currency' | 'color' | 'icon'>;

/** A named spending envelope, filled from accounts and spent down. */
export type BudgetType = 'SPENDING' | 'SAVING';

export interface BudgetRow {
  id: string;
  name: string;
  categoryId: string | null;
  category: BudgetCategory | null;
  kind: BudgetKind;
  type?: BudgetType;
  /** The built-in catch-all plan: no pot, never funded, cannot be deleted. */
  isUnplanned: boolean;
  recurrenceUnit: RecurrenceUnit | null;
  recurrenceInterval: number;
  /** "monthly", "every 6 hours" - ready to print. */
  recurrenceLabel: string | null;
  /** The noun one cycle is measured in: "month", "6 hours". */
  periodNoun: string | null;
  currency: string;
  icon?: string | null;
  color?: string | null;
  note?: string | null;
  alertThreshold: number;
  state: BudgetState;
  closedAt: string | null;

  /** How much you plan to spend per cycle - also the fill-up ceiling. */
  plannedAmount: string;
  /** What the plan was set to when this cycle opened, before any raise or cut. */
  openingPlanned: string;
  /** Net of the raises (+) and cuts (-) made to the amount during this cycle. */
  adjustedThisCycle: string;
  /** Put into the pot this cycle, including money carried over. */
  fundedAmount: string;
  /** Carried over from the previous cycle. */
  carriedIn: string;
  /** Still accepted from accounts before hitting the planned amount. */
  fillable: string;
  /** Spent out of the pot this cycle. */
  spentAmount: string;
  /** What is left to spend right now. */
  balance: string;

  pctFunded: number;
  pctOfPlan: number;
  pctSpentOfFunded: number;
  health: BudgetHealth;

  cycleIndex: number;
  /** When the user said this plan begins; not spendable before it. */
  startsAt: string;
  started: boolean;
  cycleStartedAt: string;
  nextResetAt: string | null;
  endDate: string | null;
  cycleLabel: string | null;

  createdAt: string;
  updatedAt: string;
}

/**
 * The catch-all card. Not a plan and never was a row: spending with no plan
 * behind it, presented so it has somewhere to live on the page.
 */
export interface UnplannedSummary {
  id: 'unplanned';
  name: string;
  currency: string;
  icon: string;
  color: string;
  note: string;
  /** Spent this month with no plan behind it. */
  spentAmount: string;
  lifetimeSpent: string;
  txCount: number;
}

export interface BudgetsResponse {
  items: BudgetRow[];
  unplanned: UnplannedSummary;
  totals: {
    planned: string;
    funded: string;
    spent: string;
    locked: string;
    /** Spending that never went through a funded plan, this month. */
    unplannedSpent: string;
    /** Money you have that is not in any plan - the number to act on. */
    readyToAssign: string;
    currency: string;
    activeCount: number;
    closedCount: number;
  };
}

export interface BudgetAllocation {
  id: string;
  kind: 'FUND' | 'RELEASE';
  /** Signed: negative for a give-back. */
  amount: string;
  date: string;
  note?: string | null;
  account: BudgetAccount | null;
  cycleIndex: number;
}

export interface BudgetTransaction {
  id: string;
  amount: string;
  currency: string;
  date: string;
  payee?: string | null;
  note?: string | null;
  tags: string[];
  category: BudgetCategory | null;
  account: BudgetAccount | null;
  budgetCycle: number | null;
}

/** A raise or a cut to the plan amount, filed against the cycle it happened in. */
export interface BudgetAdjustment {
  id: string;
  /** Signed: a raise is positive, a cut negative. */
  amount: string;
  date: string;
  reason?: string | null;
  cycleIndex: number;
}

export type BudgetTimelineEntry =
  | { type: 'fund' | 'release'; at: string; cycleIndex: number; entry: BudgetAllocation }
  | { type: 'spend'; at: string; cycleIndex: number; entry: BudgetTransaction }
  | { type: 'adjust'; at: string; cycleIndex: number; entry: BudgetAdjustment };

/** A finished cycle of a recurring plan, frozen at the moment it rolled over. */
export interface BudgetCycleSnapshot {
  index: number;
  label: string;
  startedAt: string;
  endedAt: string;
  /** What the plan was set to when the cycle opened. */
  openingPlanned: string;
  /** Net of the raises and cuts made during it. */
  adjustedAmount: string;
  /** Closing figure: opening + adjusted. */
  plannedAmount: string;
  carriedIn: string;
  fundedAmount: string;
  spentAmount: string;
  leftoverAmount: string;
  txCount: number;
  adjustments: BudgetAdjustment[];
}

export interface BudgetSource {
  account: BudgetAccount | null;
  available: string;
}

export interface BudgetDetail extends BudgetRow {
  /** Most recent movements only - the full list is paginated separately. */
  timeline: BudgetTimelineEntry[];
  timelineTruncated: boolean;
  allocations: BudgetAllocation[];
  /** Raises and cuts made during the cycle that is open right now. */
  adjustments: BudgetAdjustment[];
  /** Expenses charged to the cycle that is open right now. */
  cycleTxCount: number;
  sources: BudgetSource[];
  cycles: BudgetCycleSnapshot[];
  lifetime: {
    allocated: string;
    spent: string;
    txCount: number;
    firstTxAt: string | null;
    cycleCount: number;
  };
}

/** A plan offered as a "pay from" option on the transaction form. */
export interface BudgetSpendSource {
  id: string;
  name: string;
  currency: string;
  /** Null for Unplanned, which has no pot and so nothing to run out of. */
  balance: string | null;
  icon?: string | null;
  color?: string | null;
  categoryId: string | null;
  category: BudgetCategory | null;
  /** Unplanned draws on whatever the chosen wallet has free. */
  isUnplanned: boolean;
  sources: BudgetSource[];
}

export interface BudgetSourcesResponse {
  items: BudgetSpendSource[];
}

// ---------------------------------------------------------------------------
// Movements, undo, and the Money Doctor
// ---------------------------------------------------------------------------

export type MovementType =
  | 'expense'
  | 'income'
  | 'transfer'
  | 'fund'
  | 'release'
  | 'move'
  | 'adjust';

/** One thing that moved money, from any of the three ledgers. */
export interface Movement {
  /** `tx:<id>`, `alloc:<id>` or `adj:<id>`. */
  id: string;
  type: MovementType;
  title: string;
  subtitle: string | null;
  /** Signed: negative took money out or tied it up. */
  amount: string;
  currency: string;
  at: string;
  recordedAt: string;
  undoable: boolean;
  /** Why it cannot be undone, when it cannot. */
  blockedReason: string | null;
  accountId: string | null;
  budgetId: string | null;
}

export interface MovementsResponse {
  items: Movement[];
  undoWindowHours: number;
}

export interface UndoResponse {
  undone: MovementType;
  message: string;
}

export type InvariantCode = 'I2' | 'I3' | 'I4' | 'I5' | 'I6';

export interface MoneyProblem {
  code: InvariantCode;
  message: string;
  accountId?: string;
  budgetId?: string;
  amount: string;
}

export interface WalletDrift {
  account: { id: string; name: string; currency: string; icon: string | null; color: string | null };
  santimBalance: string;
  bankBalance: string;
  difference: string;
  reportedAt: string | null;
  direction: 'missing-spending' | 'missing-income';
}

/** The health check on your own books, and everything needed to act on it. */
export interface MoneyHealth {
  healthy: boolean;
  checkedAt: string;
  problems: MoneyProblem[];
  drift: WalletDrift[];
  currency: string;
  money: { real: string; reserved: string; readyToAssign: string };
  wallets: Array<{
    id: string;
    name: string;
    currency: string;
    icon: string | null;
    color: string | null;
    real: string;
    reserved: string;
    free: string;
  }>;
  plans: Array<{
    id: string;
    name: string;
    currency: string;
    icon: string | null;
    color: string | null;
    holding: string;
  }>;
}

export interface MoneyRepairResult extends Omit<MoneyHealth, 'drift' | 'money' | 'wallets' | 'plans' | 'problems'> {
  violations: MoneyProblem[];
  actions: Array<{
    kind: 'released' | 'rebalanced';
    budgetId: string;
    accountId: string;
    amount: string;
    explanation: string;
  }>;
  remaining: MoneyProblem[];
}

export interface ReadyToAssignResponse {
  items: Array<{ currency: string; amount: string }>;
}

// ---------------------------------------------------------------------------
// Payday rules
// ---------------------------------------------------------------------------

export type FundingStepMode = 'FIXED' | 'PERCENT' | 'FILL';

export interface FundingStep {
  id: string;
  budgetId: string;
  budget: {
    id: string;
    name: string;
    icon: string | null;
    color: string | null;
    currency: string;
    plannedAmount: string;
  } | null;
  position: number;
  mode: FundingStepMode;
  amount: string;
}

/** "When my salary lands, fill Rent, then Groceries, then Transport." */
export interface FundingRule {
  id: string;
  name: string;
  accountId: string | null;
  account: { id: string; name: string; type: AccountType; currency: string } | null;
  currency: string;
  minAmount: string;
  active: boolean;
  /** Ask before moving money. On by default. */
  confirmFirst: boolean;
  lastRunAt: string | null;
  steps: FundingStep[];
  createdAt: string;
}

export interface PlannedFill {
  budgetId: string;
  budgetName: string;
  icon: string | null;
  color: string | null;
  amount: string;
  mode: FundingStepMode;
  /** Set when the money ran out before this plan got its full share. */
  short: string | null;
}

export interface FundingPreview {
  ruleId: string;
  ruleName: string;
  accountId: string;
  accountName: string;
  currency: string;
  availableAmount: string;
  triggerAmount: string | null;
  fills: PlannedFill[];
  totalAmount: string;
  leftOver: string;
  /** Set on the response to a run, and on a suggestion after income lands. */
  ran?: boolean;
}

export interface Notification {
  id: string;
  type: string;
  message: string;
  link?: string | null;
  readFlag: boolean;
  createdAt: string;
}

export interface MonthSummary {
  month: string;
  currency?: string;
  income: string;
  expense: string;
  net: string;
  incomeDeltaPct: number | null;
  expenseDeltaPct: number | null;
  avgDailySpend: string;
  biggestExpense: {
    id: string;
    amount: string;
    payee?: string | null;
    note?: string | null;
    date: string;
    category?: Pick<Category, 'name' | 'icon' | 'color'> | null;
  } | null;
}

export interface SeriesPoint {
  bucket: string;
  income: string;
  expense: string;
}

export interface CategoryBreakdownItem {
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  amount: string;
  count: number;
  pct: number;
}

export interface UnnecessaryStats {
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  total: string;
  prevTotal: string;
  deltaPct: number | null;
  count: number;
}

/** One week's frozen totals, taken at the Sunday-midnight boundary. */
export interface WeekTotals {
  weekStart: string;
  weekEnd: string;
  income: string;
  expense: string;
  net: string;
  avgDailySpend: string;
  txCount: number;
  topCategory: string | null;
  topCategoryAmount: string | null;
  /** False while the week is still running. */
  sealed: boolean;
}

export interface WeeklySnapshot {
  currency: string;
  current: WeekTotals;
  previous: WeekTotals;
  delta: {
    income: number | null;
    expense: number | null;
    net: number | null;
    netAmount: string;
    expenseAmount: string;
  };
}

/** One day on the spending strip. */
export interface SpendDay {
  date: string;
  amount: string;
  spent: boolean;
  under: boolean;
}

export interface SpendingStreak {
  currency: string;
  label: string;
  /** Average daily spend across the window - the pace to stay under. */
  avgDailySpend: string;
  currentDays: number;
  bestStreak: number;
  daysUnder: number;
  dayCount: number;
  total: string;
  /** The whole window, including the days that broke the run. */
  days: SpendDay[];
}

export interface DailySpending {
  currency: string;
  label: string;
  isMonth: boolean;
  month: string | null;
  start: string;
  end: string;
  days: SpendDay[];
  stats: {
    total: string;
    pace: string;
    dayCount: number;
    daysUnder: number;
    daysOver: number;
    noSpendDays: number;
    currentStreak: number;
    bestStreak: number;
    biggestDay: { date: string; amount: string } | null;
  };
}

export interface CategoryHeatAlert {
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  amount: string;
  prevAmount: string;
  deltaPct: number;
  severity: 'low' | 'medium' | 'high';
}

export interface FamilySupportStats {
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  total: string;
  prevTotal: string;
  deltaPct: number | null;
  count: number;
  recent: { id: string; amount: string; date: string; payee?: string | null; note?: string | null }[];
}

export interface HouseholdMember {
  id: string;
  name: string;
  email: string;
  avatarId?: string;
  role: 'OWNER' | 'PARTNER';
  isYou: boolean;
}

export interface HouseholdOverview {
  id: string;
  name: string;
  role: 'OWNER' | 'PARTNER';
  members: HouseholdMember[];
  sharedAccounts: Pick<Account, 'id' | 'name' | 'type' | 'currency' | 'isShared' | 'color' | 'icon'>[];
  sharedBalance: string;
  pendingInvites: number;
}

export interface LedgerPayment {
  id: string;
  amount: string;
  date: string;
  note?: string | null;
  transactionId?: string | null;
}

export interface LedgerEntry {
  id: string;
  kind: LedgerKind;
  counterparty: string;
  title?: string | null;
  totalAmount: string;
  paid: string;
  remaining: string;
  pct: number;
  currency: string;
  dueDate?: string | null;
  note?: string | null;
  status: LedgerStatus;
  settledAt?: string | null;
  isOverdue: boolean;
  category?: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  payments: LedgerPayment[];
  createdAt: string;
  updatedAt: string;
}

export interface LedgerSummary {
  currency?: string | null;
  receivable: string;
  payable: string;
  expectedIn: string;
  expectedOut: string;
  netPosition: string;
  openCount: number;
  overdueCount: number;
  highlights: LedgerEntry[];
  overdue: LedgerEntry[];
  dueSoon: LedgerEntry[];
  forecast: {
    month: string;
    expectedIn: string;
    expectedOut: string;
    netIfOnTime: string;
    allOpenNet: string;
  };
}

export type WishlistStatus = 'WANTING' | 'PLANNED' | 'BOUGHT' | 'DROPPED';

/** The plan a want was turned into, if it has been planned. */
export interface WishPlanRef {
  id: string;
  name: string;
  icon?: string | null;
  color?: string | null;
  currency: string;
  state: BudgetState;
  kind: BudgetKind;
  plannedAmount: string;
}

/** A want is just the idea of a thing: no cost, no savings. */
export interface WishlistItem {
  id: string;
  name: string;
  priority: number;
  status: WishlistStatus;
  note?: string | null;
  link?: string | null;
  emoji?: string | null;
  /** Set once the want has been turned into a budget plan. */
  budgetId?: string | null;
  plan?: WishPlanRef | null;
  plannedAt?: string | null;
  boughtAt?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface WishlistResponse {
  items: WishlistItem[];
  /** Counts over the whole list, so tabs do not move while you search. */
  stats: {
    wanting: number;
    planned: number;
    bought: number;
    dropped: number;
    total: number;
  };
}

export type GuideCategory = 'getting-started' | 'saving' | 'spending' | 'debt';

export interface GuideSection {
  heading: string;
  body: string;
}

export interface Guide {
  id: string;
  title: string;
  emoji: string;
  category: GuideCategory;
  readMins: number;
  tagline: string;
  href?: string;
  sections: GuideSection[];
}

export interface GuideSuggestion {
  id: string;
  title: string;
  body: string;
  tone: 'tip' | 'success' | 'warning';
  guideId?: string;
  href?: string;
  cta?: string;
}

export interface GuidesOverview {
  guides: Guide[];
  suggestions: GuideSuggestion[];
}

export interface WishlistDigest {
  activeCount: number;
  plannedCount: number;
  top: WishlistItem[];
}

export interface LedgerPersonGroup {
  counterparty: string;
  openCount: number;
  receivable: string;
  expectedIn: string;
  payable: string;
  expectedOut: string;
  netRemaining: string;
  netDirection: 'in' | 'out';
  entries: LedgerEntry[];
}

export interface DashboardData {
  totalBalance: string;
  displayCurrency?: string;
  currencies?: string[];
  realBalance?: string;
  budgetLocked?: string;
  currencyBreakdown?: {
    currency: string;
    totalBalance: string;
    realBalance: string;
    budgetLocked: string;
    accountCount: number;
    month: MonthSummary;
  }[];
  convertedTotal?: {
    amount: string;
    baseCurrency: string;
    complete: boolean;
    missingRates: string[];
  };
  accounts: Account[];
  month: MonthSummary;
  budgetTotals: BudgetsResponse['totals'];
  budgetsAtRisk: BudgetRow[];
  budgets: BudgetRow[];
  recentTransactions: Transaction[];
  topCategories: CategoryBreakdownItem[];
  upcomingRecurring: (RecurringRule & { category?: { name: string; icon: string; color: string } | null })[];
  unnecessary: UnnecessaryStats;
  weeklySnapshot: WeeklySnapshot;
  spendingStreak: SpendingStreak;
  categoryHeatAlerts: CategoryHeatAlert[];
  familySupport: FamilySupportStats;
  household: HouseholdOverview | null;
  tab: LedgerSummary;
  wishlist: WishlistDigest;
}

// ---------------------------------------------------------------------------
// Analytics page (GET /analytics/page) - one payload, one screen.
// ---------------------------------------------------------------------------

export interface AnalyticsPlanRow {
  id: string;
  name: string;
  icon?: string | null;
  color?: string | null;
  kind: BudgetKind;
  cycleLabel: string | null;
  periodNoun: string | null;
  /** What the cycle opened with, before any mid-cycle raise or cut. */
  openingPlanned: string;
  /** Net of the raises (+) and cuts (-) made during the cycle. */
  adjusted: string;
  planned: string;
  funded: string;
  spent: string;
  remaining: string;
  /** Spend against the opening figure. Can exceed 100. */
  pctOfOpening: number;
}

export interface AnalyticsCommitment {
  id: string;
  name: string;
  kind: TxKind;
  amount: string;
  frequency: 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
  interval: number;
  nextRun: string;
  autoPost: boolean;
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  monthlyEquivalent: string;
}

export interface AnalyticsCounterparty {
  name: string;
  kind: 'LENT' | 'BORROWED' | 'EXPECTED_IN' | 'EXPECTED_OUT';
  outstanding: string;
  dueDate: string | null;
  overdue: boolean;
}

export interface AnalyticsPageData {
  period: {
    month: string;
    start: string;
    end: string;
    inProgress: boolean;
    daysElapsed: number;
    daysInMonth: number;
  };
  scope: {
    currency: string;
    /** Currencies held with no rate into the scoped one, so left out of totals. */
    missingRates: string[];
    complete: boolean;
  };
  history: { hasPrevious: boolean; firstTransactionAt: string | null };
  cashFlow: {
    income: string;
    expense: string;
    net: string;
    previous: { income: string; expense: string; net: string };
    deltaNetPct: number | null;
    deltaExpensePct: number | null;
    savingsRate: number | null;
  };
  unplanned: { amount: string; totalExpense: string; pct: number };
  cash: {
    real: string;
    locked: string;
    available: string;
    lockedPct: number;
    accountCount: number;
  };
  plans: {
    items: AnalyticsPlanRow[];
    totals: { opening: string; adjusted: string; spent: string; pctOfOpening: number };
    overspentCount: number;
    adjustedCount: number;
  };
  commitments: {
    monthlyOut: string;
    monthlyIn: string;
    items: AnalyticsCommitment[];
    shareOfIncome: number | null;
  };
  wishlist: {
    wanting: number;
    planned: number;
    bought: number;
    dropped: number;
    plannedValue: string;
    avgDaysToPlan: number | null;
    avgDaysToBuy: number | null;
  };
  ledger: {
    lent: string;
    lentCount: number;
    borrowed: string;
    borrowedCount: number;
    expectedIn: string;
    expectedOut: string;
    counterparties: AnalyticsCounterparty[];
    overdueCount: number;
  };
}

// --- Report endpoints the charts read -------------------------------------

export interface CategoryTotals {
  currency: string;
  total: string;
  items: {
    category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
    amount: string;
    count: number;
    pct: number;
  }[];
}

export interface IncomeVsExpense {
  currency: string;
  points: { month: string; income: string; expense: string; savingsRate: number | null }[];
}

export interface SpendHeatmapData {
  currency: string;
  year: number;
  days: { date: string; total: string }[];
}

export interface TopPayees {
  currency: string;
  items: { payee: string | null; total: string; count: number }[];
}

export interface SeasonalMonth {
  month: number;
  name: string;
  /** How many calendar months of history fed this average. */
  samples: number;
  avgIncome: string;
  avgExpense: string;
  avgNet: string;
}

export interface SeasonalReport {
  currency: string;
  monthsObserved: number;
  months: SeasonalMonth[];
  dearestMonth: SeasonalMonth | null;
  cheapestMonth: SeasonalMonth | null;
  daysOfWeek: {
    day: number;
    name: string;
    avgSpend: string;
    total: string;
    txCount: number;
    samples: number;
  }[];
  heaviestDay: { day: number; name: string; avgSpend: string; samples: number } | null;
  years: {
    year: number;
    income: string;
    expense: string;
    net: string;
    txCount: number;
    savingsRate: number | null;
  }[];
  weekly: { week: string; label: string; income: string; expense: string; net: string }[];
}

export interface CategoryMover {
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> | null;
  current: string;
  previous: string;
  change: string;
  /** Null when the category is new this month - a percentage off zero says nothing. */
  changePct: number | null;
  isNew: boolean;
  stopped: boolean;
}

export interface CategoryMovers {
  currency: string;
  month: string;
  hasPrevious: boolean;
  up: CategoryMover[];
  down: CategoryMover[];
}
