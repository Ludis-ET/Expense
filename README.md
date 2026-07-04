# Santim

A personal income & expense tracker - **Express + Prisma backend** and a **Next.js 15 frontend**, in a single pnpm workspace. Know where every birr goes.

```
.
├── backend/    Modular-monolith REST API (Express, Prisma, PostgreSQL)
├── frontend/   Next.js 15 App Router web app (Tailwind v4, SWR)
├── pnpm-workspace.yaml
└── package.json   Workspace scripts
```

## Features

**Backend** - JWT auth (access + refresh), per-user data isolation (every row scoped by `userId`), and modules for accounts, categories, transactions (income/expense/transfer), recurring rules, budgets, savings goals, analytics, a dashboard aggregator, notifications, and an optional AI assistant. Zod-validated, pino-logged, fail-fast config.

**Frontend** - a polished, responsive app with:

- Marketing **landing page** with light/dark theme
- **Auth** (login / register) - each person gets their own private account
- **Dashboard** - balance, income/spend/net stat cards with trend deltas, a spending donut, recent transactions, budgets at risk, goal progress and upcoming bills
- **Transactions** - month navigator, powerful filters (type, category, account, tag, text search), quick-add modal (press `N`), inline edit/delete, and CSV export
- **Accounts** - cash / bank / mobile-money wallets with computed balances and transfers between them
- **Budgets** - per-category monthly limits with progress bars and over-spend alerts
- **Goals** - savings goals with contributions, deadlines and "how much per month to get there"
- **Recurring** - salary, rent and subscriptions that auto-post or remind you
- **Analytics** - daily/weekly/monthly income-vs-expense trends, category breakdowns, a calendar spend heatmap, top payees, an "unnecessary spend" meter and savings rate
- **Assistant** - ask questions about your money and generate a personalized monthly review (using your own AI provider key)
- **Settings** - profile, default currency, language (English/Amharic/Oromo/Tigrinya), Ethiopian calendar option, category manager, theme picker, and AI providers
- Live **notifications**, global theming, toasts, skeletons and empty states throughout

See [`FEATURES.md`](FEATURES.md) for a full walkthrough of what you can do on each page.

## Prerequisites

- Node 20+
- pnpm 10+ (`corepack enable` will provide it)
- A PostgreSQL 16 database - the free tier of [Neon](https://neon.tech) works well and needs no local install

## Quick start

```bash
# 1. Install all workspace dependencies
pnpm install

# 2. Backend env + database
cp backend/.env.example backend/.env        # then set DATABASE_URL and JWT_SECRET
pnpm db:migrate                             # creates tables (name it "init")
pnpm db:seed                                # demo user, accounts, ~3 months of transactions

# 3. Frontend env (optional - defaults work)
cp frontend/.env.local.example frontend/.env.local

# 4. Run both apps together
pnpm dev
```

- Frontend → http://localhost:3000
- Backend  → http://localhost:4000 (the frontend proxies `/api/*` to it)

**Demo login:** `demo@example.com` / `password123`

## Workspace scripts

| Command              | What it does                                  |
| -------------------- | --------------------------------------------- |
| `pnpm dev`           | Run backend + frontend in parallel            |
| `pnpm dev:backend`   | Backend only                                  |
| `pnpm dev:frontend`  | Frontend only                                 |
| `pnpm build`         | Build both packages                           |
| `pnpm test`          | Run all tests                                 |
| `pnpm typecheck`     | Type-check both packages                      |
| `pnpm db:migrate` / `db:seed`  | Prisma migrate / seed              |

See [`backend/README.md`](backend/README.md) for the full API reference and data model.

## AI assistant (optional)

The AI features (ask-your-money, monthly review, category suggestions) use **your own** provider key - Anthropic, OpenAI or Google. Add a key under **Settings → AI providers**; keys are encrypted at rest (AES-256-GCM) and never returned to the browser. Everything else works without any AI key.

## Notes

- **Currency:** ETB by default, with per-account currencies stored. Analytics sum your default currency; v1 does not convert between currencies.
- **Privacy:** there is no team/admin layer - each account only ever sees its own data.
