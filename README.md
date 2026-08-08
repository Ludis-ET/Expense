# Santim

A personal income & expense tracker - **Express + Prisma backend** and a **Next.js 15 frontend**, in a single pnpm workspace. Know where every birr goes.

```
.
├── backend/    Modular-monolith REST API (Express, Prisma, PostgreSQL)
├── frontend/   Next.js 15 App Router web app (Tailwind v4, SWR)
├── mobile/     Flutter Android client + native bank-SMS capture
├── pnpm-workspace.yaml
└── package.json   Workspace scripts
```

> `mobile/` is a Flutter project, not a pnpm package — it is outside the
> workspace and has its own toolchain. See [`mobile/README.md`](mobile/README.md).

## Features

**Backend** - JWT auth (access + refresh), per-user data isolation (every row scoped by `userId`), and modules for accounts, categories, transactions (income/expense/transfer), recurring rules, budget plans, analytics, a dashboard aggregator, notifications, and an optional AI assistant. Zod-validated, pino-logged, fail-fast config.

**Frontend** - a polished, responsive app with:

- Marketing **landing page** with light/dark theme
- **Auth** (login / register) - each person gets their own private account
- **Dashboard** - available balance (after money set aside in plans), income/spend/net stat cards with trend deltas, a spending donut, recent transactions, plans running low and upcoming bills
- **Transactions** - month navigator, powerful filters (type, category, account, tag, text search), quick-add modal (press `N`), inline edit/delete, and CSV export
- **Accounts** - cash / bank / mobile-money wallets with computed balances and transfers between them
- **Budgets** - named spending plans (envelopes) you fill from your accounts. Filled money is reserved: it stays in the account but drops out of every "available" figure, and can only be spent against that plan. You choose the start date and any repeat cadence (every N hours → years). One-time plans close themselves once empty; recurring plans snapshot each cycle and carry leftovers forward. A built-in **Unplanned** plan catches everything you spend without reserving first, drawing straight from an account you pick. The Budgets page also hosts the **Wishlist** tab
- **Recurring** - salary, rent and subscriptions that auto-post or remind you
- **Analytics** - daily/weekly/monthly income-vs-expense trends, category breakdowns, a calendar spend heatmap, top payees, an "unnecessary spend" meter and savings rate
- **Assistant** - ask questions about your money and generate a personalized monthly review (using your own AI provider key)
- **Settings** - profile, default currency, language (English/Amharic/Oromo/Tigrinya), Ethiopian calendar option, category manager, theme picker, and AI providers
- Live **notifications**, global theming, toasts, skeletons and empty states throughout

**Mobile (Android)** — a Flutter client covering the dashboard, activity, plans and
wallets, plus the feature that only a phone can offer: **automatic bank-SMS
capture**. A native Kotlin broadcast receiver reads messages from the banks you
approve the moment they arrive — app closed, phone locked — queues them in a
local outbox, and uploads them with WorkManager. The server parses out the
amount, direction, balance and reference number, scores how confident it is, and
drops a draft in a review inbox. You tap once to record it.

Nothing posts to your ledger unseen unless you explicitly enable per-sender
auto-recording, and even then it must clear a confidence floor and still passes
through the same overdraw guard as a hand-typed entry.

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

## Mobile app

```bash
cd mobile
flutter pub get
flutter run --dart-define=SANTIM_API_URL=http://192.168.1.10:4000/api/v1
```

Use your machine's LAN IP on a real phone, or omit the define to get the
emulator default (`10.0.2.2`). The address is also editable in-app under
**Settings → Server**.

Bank-SMS capture cannot ship on Google Play — `RECEIVE_SMS` is restricted to a
short list of approved use cases that expense tracking is not on — so the app is
built for direct install (`flutter build apk`, then `adb install`). Setup, parser
tuning and the reliability caveats are covered in
[`mobile/README.md`](mobile/README.md).

## AI assistant (optional)

The AI features (ask-your-money, monthly review, category suggestions) use **your own** provider key - Anthropic, OpenAI or Google. Add a key under **Settings → AI providers**; keys are encrypted at rest (AES-256-GCM) and never returned to the browser. Everything else works without any AI key.

## Notes

- **Currency:** ETB by default, with per-account currencies stored. Analytics sum your default currency; v1 does not convert between currencies.
- **Privacy:** there is no team/admin layer - each account only ever sees its own data.
