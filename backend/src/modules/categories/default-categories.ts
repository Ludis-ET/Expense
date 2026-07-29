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
  // --- Income -------------------------------------------------------------
  { name: 'Salary', kind: CategoryKind.INCOME, icon: 'briefcase', color: '#10b981' },
  { name: 'Bonus', kind: CategoryKind.INCOME, icon: 'sparkles', color: '#22c55e' },
  { name: 'Allowance', kind: CategoryKind.INCOME, icon: 'wallet', color: '#4ade80' },
  { name: 'Freelance', kind: CategoryKind.INCOME, icon: 'laptop', color: '#14b8a6' },
  { name: 'Business', kind: CategoryKind.INCOME, icon: 'store', color: '#059669' },
  { name: 'Side Hustle', kind: CategoryKind.INCOME, icon: 'wrench', color: '#0d9488' },
  { name: 'Rental Income', kind: CategoryKind.INCOME, icon: 'home', color: '#16a34a' },
  { name: 'Investment Returns', kind: CategoryKind.INCOME, icon: 'trending-up', color: '#65a30d' },
  { name: 'Interest', kind: CategoryKind.INCOME, icon: 'piggy-bank', color: '#84cc16' },
  { name: 'Remittance Received', kind: CategoryKind.INCOME, icon: 'hand-coins', color: '#06b6d4' },
  { name: 'Gift Received', kind: CategoryKind.INCOME, icon: 'gift', color: '#a3e635' },
  { name: 'Loan Repayment', kind: CategoryKind.INCOME, icon: 'banknote', color: '#0891b2' },
  { name: 'Refund', kind: CategoryKind.INCOME, icon: 'repeat', color: '#2dd4bf' },
  { name: 'Sold Something', kind: CategoryKind.INCOME, icon: 'shopping-cart', color: '#34d399' },
  { name: 'Pension', kind: CategoryKind.INCOME, icon: 'shield', color: '#15803d' },
  { name: 'Other Income', kind: CategoryKind.INCOME, icon: 'plus-circle', color: '#6ee7b7' },

  // --- Expense: food ------------------------------------------------------
  { name: 'Food & Groceries', kind: CategoryKind.EXPENSE, icon: 'shopping-basket', color: '#f59e0b' },
  { name: 'Restaurants & Cafés', kind: CategoryKind.EXPENSE, icon: 'utensils', color: '#fb923c' },
  { name: 'Coffee & Tea', kind: CategoryKind.EXPENSE, icon: 'coffee', color: '#d97706' },

  // --- Expense: getting around -------------------------------------------
  { name: 'Transport', kind: CategoryKind.EXPENSE, icon: 'bus', color: '#3b82f6' },
  { name: 'Taxi & Ride-hailing', kind: CategoryKind.EXPENSE, icon: 'car', color: '#2563eb' },
  { name: 'Fuel', kind: CategoryKind.EXPENSE, icon: 'fuel', color: '#1d4ed8' },
  { name: 'Vehicle Maintenance', kind: CategoryKind.EXPENSE, icon: 'wrench', color: '#60a5fa' },

  // --- Expense: home ------------------------------------------------------
  { name: 'Rent', kind: CategoryKind.EXPENSE, icon: 'home', color: '#8b5cf6' },
  { name: 'Utilities', kind: CategoryKind.EXPENSE, icon: 'plug-zap', color: '#06b6d4' },
  { name: 'Internet', kind: CategoryKind.EXPENSE, icon: 'wifi', color: '#0ea5e9' },
  { name: 'Airtime & Data', kind: CategoryKind.EXPENSE, icon: 'smartphone', color: '#38bdf8' },
  { name: 'Household Items', kind: CategoryKind.EXPENSE, icon: 'shopping-cart', color: '#7c3aed' },
  { name: 'Repairs & Maintenance', kind: CategoryKind.EXPENSE, icon: 'wrench', color: '#a78bfa' },

  // --- Expense: health & self --------------------------------------------
  { name: 'Health', kind: CategoryKind.EXPENSE, icon: 'heart-pulse', color: '#ef4444' },
  { name: 'Medicine & Pharmacy', kind: CategoryKind.EXPENSE, icon: 'pill', color: '#f87171' },
  { name: 'Fitness & Gym', kind: CategoryKind.EXPENSE, icon: 'dumbbell', color: '#dc2626' },
  { name: 'Personal Care', kind: CategoryKind.EXPENSE, icon: 'heart', color: '#fb7185' },

  // --- Expense: learning --------------------------------------------------
  { name: 'Education', kind: CategoryKind.EXPENSE, icon: 'graduation-cap', color: '#6366f1' },
  { name: 'Books & Courses', kind: CategoryKind.EXPENSE, icon: 'book-open', color: '#818cf8' },

  // --- Expense: living ----------------------------------------------------
  { name: 'Entertainment', kind: CategoryKind.EXPENSE, icon: 'clapperboard', color: '#ec4899' },
  { name: 'Music & Streaming', kind: CategoryKind.EXPENSE, icon: 'music', color: '#f472b6' },
  { name: 'Games', kind: CategoryKind.EXPENSE, icon: 'gamepad-2', color: '#e879f9' },
  { name: 'Travel & Holidays', kind: CategoryKind.EXPENSE, icon: 'plane', color: '#22d3ee' },
  { name: 'Shopping', kind: CategoryKind.EXPENSE, icon: 'shopping-bag', color: '#d946ef' },
  { name: 'Clothing', kind: CategoryKind.EXPENSE, icon: 'shirt', color: '#c026d3' },
  { name: 'Pets', kind: CategoryKind.EXPENSE, icon: 'paw-print', color: '#a16207' },

  // --- Expense: people ----------------------------------------------------
  { name: 'Gifts', kind: CategoryKind.EXPENSE, icon: 'gift', color: '#f43f5e' },
  { name: 'Family Support', kind: CategoryKind.EXPENSE, icon: 'users', color: '#a855f7' },
  { name: 'Celebrations & Events', kind: CategoryKind.EXPENSE, icon: 'sparkles', color: '#e11d48' },
  { name: 'Charity & Donations', kind: CategoryKind.EXPENSE, icon: 'heart', color: '#be123c' },

  // --- Expense: money out -------------------------------------------------
  { name: 'Debt & Loans', kind: CategoryKind.EXPENSE, icon: 'landmark', color: '#dc2626' },
  { name: 'Bank & Transfer Fees', kind: CategoryKind.EXPENSE, icon: 'credit-card', color: '#78716c' },
  { name: 'Insurance', kind: CategoryKind.EXPENSE, icon: 'shield', color: '#0f766e' },
  { name: 'Taxes', kind: CategoryKind.EXPENSE, icon: 'landmark', color: '#991b1b' },
  { name: 'Subscriptions', kind: CategoryKind.EXPENSE, icon: 'repeat', color: '#64748b' },
  { name: 'Savings & Investments', kind: CategoryKind.EXPENSE, icon: 'piggy-bank', color: '#0369a1' },

  // --- Expense: the honest ones ------------------------------------------
  { name: 'Unnecessary', kind: CategoryKind.EXPENSE, icon: 'flame', color: '#f97316' },
  { name: 'Other', kind: CategoryKind.EXPENSE, icon: 'circle-ellipsis', color: '#94a3b8' },
];

/** Name of the impulse-spend category used by the "unnecessary spend" analytics callout. */
export const UNNECESSARY_CATEGORY_NAME = 'Unnecessary';

/** Remittances & family support - tracked on the dashboard. */
export const FAMILY_SUPPORT_CATEGORY_NAME = 'Family Support';
