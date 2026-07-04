import bcrypt from 'bcryptjs';
import { AccountType, Frequency, PrismaClient, TxKind } from '../generated/client/index.js';
import { DEFAULT_CATEGORIES } from '../src/modules/categories/default-categories.js';

const prisma = new PrismaClient();

const DAY = 24 * 60 * 60 * 1000;

function daysAgo(days: number, hour = 12): Date {
  const d = new Date(Date.now() - days * DAY);
  d.setUTCHours(hour, 0, 0, 0);
  return d;
}

/** Deterministic pseudo-random so re-seeding produces the same data. */
function makeRng(seed: number) {
  let s = seed;
  return () => {
    s = (s * 1103515245 + 12345) % 2 ** 31;
    return s / 2 ** 31;
  };
}

async function main() {
  const passwordHash = await bcrypt.hash('password123', 12);

  // Idempotent: wipe and recreate the demo user so re-seeding is clean.
  await prisma.user.deleteMany({ where: { email: 'demo@example.com' } });

  const user = await prisma.user.create({
    data: {
      email: 'demo@example.com',
      name: 'Kiflay Mehari',
      passwordHash,
      locale: 'en',
      currency: 'ETB',
    },
  });

  // --- Categories (same set every registered user gets) ---
  await prisma.category.createMany({
    data: DEFAULT_CATEGORIES.map((c) => ({ ...c, userId: user.id, isDefault: true })),
  });
  const categories = await prisma.category.findMany({ where: { userId: user.id } });
  const cat = (name: string) => {
    const found = categories.find((c) => c.name === name);
    if (!found) throw new Error(`Seed category missing: ${name}`);
    return found;
  };

  // --- Accounts ---
  // Opening balances are set generously so accounts stay positive across the
  // ~3 months of seeded spending (routing below keeps each account realistic).
  const cash = await prisma.account.create({
    data: { userId: user.id, name: 'Cash', type: AccountType.CASH, openingBalance: 18000, icon: 'banknote', color: '#22c55e' },
  });
  const cbe = await prisma.account.create({
    data: { userId: user.id, name: 'CBE', type: AccountType.BANK, openingBalance: 20000, icon: 'landmark', color: '#8b5cf6', isDefault: true },
  });
  const telebirr = await prisma.account.create({
    data: { userId: user.id, name: 'Telebirr', type: AccountType.MOBILE_MONEY, openingBalance: 9000, icon: 'smartphone', color: '#0ea5e9' },
  });

  // --- ~3 months of transactions ---
  const rng = makeRng(42);
  const txns: {
    kind: TxKind;
    amount: number;
    date: Date;
    accountId: string;
    transferAccountId?: string;
    categoryId?: string;
    payee?: string;
    note?: string;
    tags?: string[];
  }[] = [];

  // Monthly salary (28th) and rent (1st) for the past 3 cycles.
  for (const monthsBack of [2, 1, 0]) {
    const now = new Date();
    const salaryDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - monthsBack, 28, 9));
    const rentDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - monthsBack, 1, 10));
    if (salaryDate <= now) {
      txns.push({
        kind: TxKind.INCOME, amount: 45000, date: salaryDate, accountId: cbe.id,
        categoryId: cat('Salary').id, payee: 'Employer', note: 'Monthly salary',
      });
    }
    if (rentDate <= now) {
      txns.push({
        kind: TxKind.EXPENSE, amount: 12000, date: rentDate, accountId: cbe.id,
        categoryId: cat('Rent').id, payee: 'Landlord', note: 'Monthly rent',
      });
    }
  }

  // Freelance payments - one recent so the current month always shows income.
  txns.push(
    { kind: TxKind.INCOME, amount: 8500, date: daysAgo(52), accountId: cbe.id, categoryId: cat('Freelance').id, payee: 'Design client', note: 'Logo project', tags: ['side-hustle'] },
    { kind: TxKind.INCOME, amount: 6200, date: daysAgo(18), accountId: telebirr.id, categoryId: cat('Freelance').id, payee: 'Web client', note: 'Landing page', tags: ['side-hustle'] },
    { kind: TxKind.INCOME, amount: 4000, date: daysAgo(1), accountId: telebirr.id, categoryId: cat('Freelance').id, payee: 'Tutoring', note: 'Weekend session', tags: ['side-hustle'] },
  );

  // Weekly groceries (paid from the bank account).
  const groceryPayees = ['Shoa Supermarket', 'Fresh Corner', 'Queens Supermarket'];
  for (let week = 0; week < 13; week++) {
    const amount = Math.round(800 + rng() * 1700);
    txns.push({
      kind: TxKind.EXPENSE, amount, date: daysAgo(week * 7 + Math.floor(rng() * 3), 18),
      accountId: cbe.id,
      categoryId: cat('Food & Groceries').id,
      payee: groceryPayees[Math.floor(rng() * groceryPayees.length)],
    });
  }

  // Transport 3-5x/week (cash).
  for (let day = 0; day < 92; day++) {
    const rides = rng();
    if (rides < 0.5) continue;
    const amount = Math.round(40 + rng() * 360);
    txns.push({
      kind: TxKind.EXPENSE, amount, date: daysAgo(day, 8 + Math.floor(rng() * 10)),
      accountId: cash.id,
      categoryId: cat('Transport').id,
      payee: rng() > 0.5 ? 'Ride' : 'Minibus',
    });
  }

  // Airtime top-ups every ~10 days.
  for (let i = 0; i < 9; i++) {
    txns.push({
      kind: TxKind.EXPENSE, amount: Math.round(100 + rng() * 400), date: daysAgo(i * 10 + Math.floor(rng() * 4)),
      accountId: telebirr.id, categoryId: cat('Airtime & Data').id, payee: 'Ethio Telecom',
    });
  }

  // Utilities monthly-ish.
  for (const d of [80, 49, 20]) {
    txns.push(
      { kind: TxKind.EXPENSE, amount: Math.round(600 + rng() * 500), date: daysAgo(d), accountId: cbe.id, categoryId: cat('Utilities').id, payee: 'EEU', note: 'Electricity' },
      { kind: TxKind.EXPENSE, amount: Math.round(250 + rng() * 250), date: daysAgo(d - 2), accountId: cbe.id, categoryId: cat('Utilities').id, payee: 'AAWSA', note: 'Water' },
    );
  }

  // Entertainment, shopping, health, gifts, family support, unnecessary buys.
  const extras: [string, string, number, number, string?][] = [
    ['Entertainment', 'Cinema', 450, 75],
    ['Entertainment', 'Cafe with friends', 380, 60],
    ['Entertainment', 'Concert ticket', 1200, 33],
    ['Entertainment', 'Cafe', 260, 12],
    ['Shopping', 'Bole Boutique', 2800, 68],
    ['Shopping', 'Shoe store', 1900, 25],
    ['Health', 'Pharmacy', 540, 58],
    ['Health', 'Clinic visit', 1500, 41],
    ['Education', 'Online course', 1100, 47, 'learning'],
    ['Gifts', 'Wedding gift', 2000, 55],
    ['Gifts', 'Birthday gift', 800, 15],
    ['Family Support', 'Sent to mom', 3000, 62],
    ['Family Support', 'Sent to mom', 3000, 31],
    ['Family Support', 'Sent to mom', 3000, 2],
    ['Unnecessary', 'Late-night snacks', 350, 70],
    ['Unnecessary', 'Impulse gadget', 1600, 44],
    ['Unnecessary', 'Another coffee', 180, 26],
    ['Unnecessary', 'Streaming trinket', 420, 2],
    ['Unnecessary', 'Window-shopping haul', 950, 1],
  ];
  for (const [category, payee, amount, days, tag] of extras) {
    // "Unnecessary" impulse buys come from cash/telebirr; everything else from the bank.
    const accountId = category === 'Unnecessary' ? (rng() > 0.5 ? cash.id : telebirr.id) : cbe.id;
    txns.push({
      kind: TxKind.EXPENSE, amount, date: daysAgo(days), accountId,
      categoryId: cat(category).id, payee, tags: tag ? [tag] : [],
    });
  }

  // Subscriptions (internet).
  for (const d of [78, 47, 17]) {
    txns.push({
      kind: TxKind.EXPENSE, amount: 1100, date: daysAgo(d), accountId: cbe.id,
      categoryId: cat('Subscriptions').id, payee: 'Ethio Telecom', note: 'Home internet',
    });
  }

  // Transfers CBE → Telebirr / Cash.
  txns.push(
    { kind: TxKind.TRANSFER, amount: 5000, date: daysAgo(59), accountId: cbe.id, transferAccountId: telebirr.id, note: 'Top up Telebirr' },
    { kind: TxKind.TRANSFER, amount: 4000, date: daysAgo(27), accountId: cbe.id, transferAccountId: telebirr.id, note: 'Top up Telebirr' },
    { kind: TxKind.TRANSFER, amount: 3000, date: daysAgo(6), accountId: cbe.id, transferAccountId: cash.id, note: 'Cash withdrawal' },
  );

  await prisma.transaction.createMany({
    data: txns.map((t) => ({ ...t, userId: user.id, currency: 'ETB', tags: t.tags ?? [] })),
  });

  // --- Recurring rules (nextRun in the future so seeding doesn't double-post) ---
  const nextMonth = (day: number) => {
    const now = new Date();
    const candidate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), day, 9));
    return candidate > now
      ? candidate
      : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, day, 9));
  };

  await prisma.recurringRule.createMany({
    data: [
      {
        userId: user.id, name: 'Salary', kind: TxKind.INCOME, amount: 45000, currency: 'ETB',
        accountId: cbe.id, categoryId: cat('Salary').id, payee: 'Employer',
        frequency: Frequency.MONTHLY, dayOfMonth: 28, nextRun: nextMonth(28), autoPost: true,
      },
      {
        userId: user.id, name: 'Rent', kind: TxKind.EXPENSE, amount: 12000, currency: 'ETB',
        accountId: cbe.id, categoryId: cat('Rent').id, payee: 'Landlord',
        frequency: Frequency.MONTHLY, dayOfMonth: 1, nextRun: nextMonth(1), autoPost: true,
      },
      {
        userId: user.id, name: 'Home internet', kind: TxKind.EXPENSE, amount: 1100, currency: 'ETB',
        accountId: cbe.id, categoryId: cat('Subscriptions').id, payee: 'Ethio Telecom',
        frequency: Frequency.MONTHLY, dayOfMonth: 15, nextRun: nextMonth(15), autoPost: true,
      },
      {
        userId: user.id, name: 'Gym membership', kind: TxKind.EXPENSE, amount: 1500, currency: 'ETB',
        accountId: cash.id, categoryId: cat('Health').id, payee: 'Fitness First',
        frequency: Frequency.MONTHLY, dayOfMonth: 5, nextRun: nextMonth(5), autoPost: false,
      },
    ],
  });

  // --- Budgets ---
  await prisma.budget.createMany({
    data: [
      { userId: user.id, categoryId: cat('Food & Groceries').id, amount: 10000, alertThreshold: 80 },
      { userId: user.id, categoryId: cat('Transport').id, amount: 4000, alertThreshold: 80 },
      { userId: user.id, categoryId: cat('Unnecessary').id, amount: 1500, alertThreshold: 75 },
      { userId: user.id, categoryId: cat('Entertainment').id, amount: 3000, alertThreshold: 80 },
    ],
  });

  // --- Savings goal with contributions ---
  await prisma.savingsGoal.create({
    data: {
      userId: user.id,
      name: 'Emergency Fund',
      icon: 'shield',
      color: '#10b981',
      targetAmount: 100000,
      deadline: new Date(Date.now() + 8 * 30 * DAY),
      note: 'Six months of expenses, just in case.',
      contributions: {
        create: [
          { amount: 10000, date: daysAgo(75), note: 'Initial deposit' },
          { amount: 9000, date: daysAgo(45) },
          { amount: 9000, date: daysAgo(14) },
        ],
      },
    },
  });

  await prisma.notification.create({
    data: {
      userId: user.id,
      type: 'welcome',
      message: 'Welcome to Santim! Your demo data is ready - explore the dashboard.',
      link: '/dashboard',
    },
  });

  console.log(`Seeded demo user ${user.email} with ${txns.length} transactions.`);
  console.log('Login with demo@example.com / password123');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
