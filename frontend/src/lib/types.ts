export type TxKind = 'INCOME' | 'EXPENSE' | 'TRANSFER';
export type CategoryKind = 'INCOME' | 'EXPENSE';
export type AccountType = 'CASH' | 'BANK' | 'MOBILE_MONEY' | 'CARD' | 'OTHER';
export type Frequency = 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';

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

export interface DashboardData {
  totalBalance: string;
  accounts: Account[];
  month: MonthSummary;
  budgetsAtRisk: BudgetRow[];
  goals: SavingsGoal[];
  recentTransactions: Transaction[];
  topCategories: CategoryBreakdownItem[];
  upcomingRecurring: (RecurringRule & { category?: { name: string; icon: string; color: string } | null })[];
  unnecessary: UnnecessaryStats;
}
