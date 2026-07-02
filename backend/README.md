# Santim — Backend API

The Santim REST API built as a **modular monolith** in Node.js + TypeScript.
One deployable backend with clean internal module boundaries over a single
PostgreSQL database. Every row is owned by exactly one user (`userId` scoping),
so accounts are fully private to each person.

## Tech stack

| Concern        | Choice                              |
| -------------- | ----------------------------------- |
| Language       | TypeScript (ESM, Node 20+)          |
| HTTP           | Express 4                           |
| ORM / DB       | Prisma + PostgreSQL                 |
| Validation     | Zod (every request body/query/param)|
| Auth           | JWT access + refresh tokens, bcrypt |
| Logging        | pino / pino-http                    |
| Tests          | Vitest                              |
| Database host  | Any PostgreSQL 16 instance (e.g. Neon) |

## Project layout

```
src/
  config/env.ts          Typed, validated environment (fail-fast)
  core/
    db.ts                Shared Prisma client
    logger.ts            pino logger
    errors.ts            Typed AppError hierarchy
    http.ts              asyncHandler
    crypto.ts            AES-256-GCM encrypt/decrypt for stored AI keys
    context.ts           AuthUser + Express.Request augmentation
    middleware/          auth (JWT), validate (Zod), error-handler
  modules/
    auth/                register / login / refresh, JWT helpers
    users/               GET/PUT /users/me
    accounts/            wallets + computed balances
    categories/          income/expense categories (+ default set)
    transactions/        income / expense / transfer + rich filtering
    recurring/           recurring rules + lazy catch-up engine
    budgets/             per-category monthly budgets + alerts
    goals/               savings goals + contributions
    analytics/           summary, series, breakdowns, heatmap, payees
    dashboard/           single aggregated dashboard payload
    ai/                  bring-your-own-key assistant (ask, review, categorize)
    notifications/       in-app notifications
  routes.ts              Mounts modules under /api/v1
  app.ts                 Express app assembly (helmet, cors, routes)
  server.ts              Entry point + graceful shutdown
prisma/
  schema.prisma          Full data model
  seed.ts                Demo user, accounts, ~3 months of transactions
tests/                   Vitest unit tests
```

## Getting started

```bash
# 1. Install dependencies
pnpm install

# 2. Configure environment
cp .env.example .env        # then edit DATABASE_URL and JWT_SECRET

# 3. Point DATABASE_URL at any PostgreSQL 16 instance
#    (e.g. a free Neon project — see repo root README for details)

# 4. Create the schema and seed demo data
pnpm db:migrate             # creates tables (name the migration "init")
pnpm db:seed

# 5. Run the API (http://localhost:4000)
pnpm dev
```

Health check: `GET http://localhost:4000/health`

### Demo credentials (after seeding)

`demo@example.com` / `password123`

## API reference

All routes are under `/api/v1`. Everything except `/auth/*` requires a
`Authorization: Bearer <accessToken>` header.

| Method   | Path                                    | Notes |
| -------- | --------------------------------------- | ----- |
| POST     | `/auth/register` · `/auth/login` · `/auth/refresh` | public |
| GET/PUT  | `/users/me`                             | profile + preferences |
| GET/POST | `/accounts`, PUT/DELETE `/accounts/:id` | balances computed on read |
| GET/POST | `/categories`, PUT/DELETE `/categories/:id` | `?kind=`, delete `?reassignTo=` |
| GET/POST | `/transactions`, GET/PUT/DELETE `/transactions/:id`, GET `/transactions/tags` | filters: from,to,kind,categoryId,accountId,tag,q,min,max,page,pageSize,sort |
| GET/POST | `/recurring`, PUT/DELETE `/recurring/:id`, POST `/recurring/:id/run-now` | |
| GET      | `/budgets?month=YYYY-MM`, PUT/DELETE `/budgets/:categoryId` | joined with month spend |
| GET/POST | `/goals`, PUT/DELETE `/goals/:id`, POST/DELETE `/goals/:id/contributions[/:cid]` | |
| GET      | `/analytics/{summary,series,categories,income-vs-expense,heatmap,payees,unnecessary}` | |
| GET      | `/dashboard`                            | one aggregated payload |
| POST     | `/ai/ask` · `/ai/review` · `/ai/categorize` | needs a provider key |
| GET/PUT  | `/ai/settings`, POST `/ai/settings/test`, GET `/ai/status` | manage provider keys |
| GET      | `/notifications`, POST `/notifications/:id/read`, `/notifications/read-all` | |

## Privacy & isolation

The JWT carries the user's `id`; every service query is filtered by it
(`assertOwnedAccount`, `assertOwnedTransaction`, …) so one user can never read or
mutate another's data. This is the single most important invariant in the
codebase — keep it intact when adding modules.

## Recurring execution

Recurring rules are materialized **lazily**: a debounced middleware on the
dashboard/transactions/analytics/recurring routes calls `catchUpUser`, which posts
any due occurrences (or fires reminders) inside a single transaction. No background
job server is required, and it stays correct on hosts that sleep the process.
`advanceNextRun` handles interval math and month-end clamping and is unit-tested.

## AI assistant

Provider keys (Anthropic / OpenAI / Google) are stored per-user, encrypted at rest
with AES-256-GCM (`core/crypto.ts`), and tried in priority order with fallthrough.
The features (`ask`, `monthlyReview`, `categorize`) build a compact finance snapshot
so prompts stay small. No key is required to use the rest of the API.

## Scripts

| Command              | Description                          |
| -------------------- | ------------------------------------ |
| `pnpm dev`           | Hot-reload dev server (tsx)          |
| `pnpm build`         | Compile to `dist/`                   |
| `pnpm start`         | Run compiled server                  |
| `pnpm typecheck`     | `tsc --noEmit`                       |
| `pnpm test`          | Run Vitest                           |
| `pnpm db:migrate`    | Create/apply a dev migration         |
| `pnpm db:seed`       | Seed demo data                       |
| `pnpm db:studio`     | Open Prisma Studio                   |
