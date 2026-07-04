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
  balance: string;
  icon?: string | null;
  color?: string | null;
  isDefault: boolean;
  archived: boolean;
  isShared?: boolean;
  householdId?: string | null;
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
  note?: string | null;
  payee?: string | null;
  tags: string[];
  recurringRuleId?: string | null;
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

export interface BudgetRow {
  id: string;
  categoryId: string;
  category: Pick<Category, 'id' | 'name' | 'icon' | 'color'> & { archived?: boolean };
  amount: string;
  alertThreshold: number;
  spent: string;
  remaining: string;
  pct: number;
  status: 'ok' | 'warning' | 'over';
}

export interface BudgetsResponse {
  items: BudgetRow[];
  totals: { budgeted: string; spent: string; remaining: string };
}

export interface GoalContribution {
  id: string;
  amount: string;
  date: string;
  note?: string | null;
}

export interface SavingsGoal {
  id: string;
  name: string;
  icon?: string | null;
  color?: string | null;
  targetAmount: string;
  saved: string;
  pct: number;
  monthlyNeeded: string | null;
  deadline?: string | null;
  note?: string | null;
  achievedAt?: string | null;
  contributions: GoalContribution[];
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

export interface WeeklySnapshot {
  weekStart: string;
  income: string;
  expense: string;
  net: string;
  prevIncome: string;
  prevExpense: string;
  incomeDeltaPct: number | null;
  expenseDeltaPct: number | null;
}

export interface SpendingStreak {
  currentDays: number;
  label: string;
  avgDailyLimit: string;
  bestStreak: number;
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
  currencyBreakdown?: {
    currency: string;
    totalBalance: string;
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
  budgetsAtRisk: BudgetRow[];
  goals: SavingsGoal[];
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
}
