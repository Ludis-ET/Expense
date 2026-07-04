import { CategoryKind } from '../../core/prisma.js';

/**
 * Categories every new user starts with. Created inside the registration
 * transaction and reused by the seed script so demo and real accounts match.
 * `icon` is a lucide-react icon name rendered by the frontend icon map.
 */
export interface DefaultCategory {
  name: string;
  kind: CategoryKind;
  icon: string;
  color: string;
}

export const DEFAULT_CATEGORIES: DefaultCategory[] = [
  // --- Income ---
  { name: 'Salary', kind: CategoryKind.INCOME, icon: 'briefcase', color: '#10b981' },
  { name: 'Freelance', kind: CategoryKind.INCOME, icon: 'laptop', color: '#14b8a6' },
  { name: 'Business', kind: CategoryKind.INCOME, icon: 'store', color: '#22c55e' },
  { name: 'Gift Received', kind: CategoryKind.INCOME, icon: 'gift', color: '#84cc16' },
  { name: 'Loan Repayment', kind: CategoryKind.INCOME, icon: 'hand-coins', color: '#059669' },
  { name: 'Other Income', kind: CategoryKind.INCOME, icon: 'plus-circle', color: '#65a30d' },

  // --- Expense ---
  { name: 'Food & Groceries', kind: CategoryKind.EXPENSE, icon: 'shopping-basket', color: '#f59e0b' },
  { name: 'Transport', kind: CategoryKind.EXPENSE, icon: 'bus', color: '#3b82f6' },
  { name: 'Rent', kind: CategoryKind.EXPENSE, icon: 'home', color: '#8b5cf6' },
  { name: 'Utilities', kind: CategoryKind.EXPENSE, icon: 'plug-zap', color: '#06b6d4' },
  { name: 'Airtime & Data', kind: CategoryKind.EXPENSE, icon: 'smartphone', color: '#0ea5e9' },
  { name: 'Health', kind: CategoryKind.EXPENSE, icon: 'heart-pulse', color: '#ef4444' },
  { name: 'Education', kind: CategoryKind.EXPENSE, icon: 'graduation-cap', color: '#6366f1' },
  { name: 'Entertainment', kind: CategoryKind.EXPENSE, icon: 'clapperboard', color: '#ec4899' },
  { name: 'Shopping', kind: CategoryKind.EXPENSE, icon: 'shopping-bag', color: '#d946ef' },
  { name: 'Gifts', kind: CategoryKind.EXPENSE, icon: 'gift', color: '#f43f5e' },
  { name: 'Family Support', kind: CategoryKind.EXPENSE, icon: 'users', color: '#a855f7' },
  { name: 'Debt & Loans', kind: CategoryKind.EXPENSE, icon: 'landmark', color: '#dc2626' },
  { name: 'Subscriptions', kind: CategoryKind.EXPENSE, icon: 'repeat', color: '#64748b' },
  { name: 'Unnecessary', kind: CategoryKind.EXPENSE, icon: 'flame', color: '#f97316' },
  { name: 'Other', kind: CategoryKind.EXPENSE, icon: 'circle-ellipsis', color: '#94a3b8' },
];

/** Name of the impulse-spend category used by the "unnecessary spend" analytics callout. */
export const UNNECESSARY_CATEGORY_NAME = 'Unnecessary';

/** Remittances & family support - tracked on the dashboard. */
export const FAMILY_SUPPORT_CATEGORY_NAME = 'Family Support';
