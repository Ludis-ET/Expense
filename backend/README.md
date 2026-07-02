# Research Tracker — MVP

A research-management SaaS built as a **modular monolith** in Node.js + TypeScript.
One deployable backend with clean internal module boundaries (`auth`, `users`,
`projects`, `budget`) over a single PostgreSQL database. Multi-tenant from day one
via `orgId` row scoping, so microservices can be extracted later without re-architecting.

This is the MVP slice of a larger plan: **auth + projects/teams + budget/expense tracking**.
Publications, datasets, experiments, milestones, ideas, and notifications already exist in
the data model and are ready to grow into their own modules.

## Tech stack

| Concern        | Choice                              |
| -------------- | ----------------------------------- |
| Language       | TypeScript (ESM, Node 20+)          |
| HTTP           | Express 4                           |
| ORM / DB       | Prisma + PostgreSQL                 |
| Validation     | Zod (every request body/query/param)|
| Auth           | JWT access + refresh tokens, bcrypt |
| Authorization  | Role-based (`requireRole`)          |
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
    context.ts           AuthUser + Express.Request augmentation
    middleware/          auth (JWT), rbac, validate (Zod), error-handler
  modules/
    auth/                register / login / refresh, JWT helpers
    users/               GET/PUT /users/me
    projects/            project CRUD + team membership
    budget/              budget items + expenses + approval workflow
  routes.ts              Mounts modules under /api/v1
  app.ts                 Express app assembly (helmet, cors, routes)
  server.ts              Entry point + graceful shutdown
prisma/
  schema.prisma          Full data model (12 entities)
  seed.ts                Demo org, users, project, budget
tests/                   Vitest unit tests
```

## Getting started

```bash
# 1. Install dependencies
npm install

# 2. Configure environment
cp .env.example .env        # then edit DATABASE_URL and JWT_SECRET

# 3. Point DATABASE_URL at any PostgreSQL 16 instance
#    (e.g. a free Neon project — see repo root README for details)

# 4. Create the schema and seed demo data
npm run db:migrate          # creates tables (name the migration "init")
npm run db:seed

# 5. Run the API (http://localhost:4000)
npm run dev
```

Health check: `GET http://localhost:4000/health`

### Demo credentials (after seeding)

`admin@example.com` / `password123`  — ADMIN of "Addis Ababa University"
`researcher@example.com` / `password123` — RESEARCHER

## Quick API tour

```bash
# Register a new org + admin
curl -X POST localhost:4000/api/v1/auth/register \
  -H 'content-type: application/json' \
  -d '{"name":"Dr Smith","email":"smith@lab.org","password":"password123","orgName":"Smith Lab"}'

# Log in (returns accessToken + refreshToken)
TOKEN=$(curl -s -X POST localhost:4000/api/v1/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"password123"}' | jq -r .accessToken)

# Create a project
curl -X POST localhost:4000/api/v1/projects \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"title":"New Study","currency":"ETB"}'

# List projects (tenant-scoped to your org)
curl localhost:4000/api/v1/projects -H "authorization: Bearer $TOKEN"
```

## API reference (MVP)

| Method   | Path                                          | Role            |
| -------- | --------------------------------------------- | --------------- |
| POST     | `/api/v1/auth/register`                       | public          |
| POST     | `/api/v1/auth/login`                          | public          |
| POST     | `/api/v1/auth/refresh`                        | public          |
| GET/PUT  | `/api/v1/users/me`                            | any authed      |
| GET      | `/api/v1/projects`                            | any authed      |
| POST     | `/api/v1/projects`                            | admin/lead/researcher |
| GET/PUT  | `/api/v1/projects/:id`                        | any authed (own org) |
| DELETE   | `/api/v1/projects/:id`                        | admin/lead      |
| POST     | `/api/v1/projects/:id/team`                   | admin/lead      |
| DELETE   | `/api/v1/projects/:id/team/:userId`           | admin/lead      |
| GET      | `/api/v1/projects/:projectId/budget`          | any authed (own org) |
| POST     | `/api/v1/projects/:projectId/budget`          | admin/lead/finance |
| PUT/DEL  | `/api/v1/budget/:budgetItemId`                | admin/lead/finance |
| POST     | `/api/v1/budget/:budgetItemId/expenses`       | any authed      |
| POST     | `/api/v1/expenses/:expenseId/decision`        | admin/lead/finance |

## Multi-tenancy & isolation

Every tenant is an `Organization`. The JWT carries `orgId`; every service query is
filtered by it (`findOwnedProject`, `assertOwnedBudgetItem`, …) so one org can never
read or mutate another's data. This is the single most important invariant in the
codebase — keep it intact when adding modules.

## Scripts

| Command              | Description                          |
| -------------------- | ------------------------------------ |
| `npm run dev`        | Hot-reload dev server (tsx)          |
| `npm run build`      | Compile to `dist/`                   |
| `npm start`          | Run compiled server                  |
| `npm run typecheck`  | `tsc --noEmit`                       |
| `npm test`           | Run Vitest                           |
| `npm run db:migrate` | Create/apply a dev migration         |
| `npm run db:seed`    | Seed demo data                       |
| `npm run db:studio`  | Open Prisma Studio                   |

## Deliberately deferred

Per the design review, these are **not** in the MVP and should arrive as later phases:
microservice extraction, Kubernetes/Terraform, Elasticsearch/vector search, AI
summarization, ORCID/CrossRef integration, i18n UI, PWA/offline, and payment gateways.
The module boundaries here are designed so each can be added without rework.

> **Compliance note:** Ethiopian PDPP requires in-country storage of Ethiopian personal
> data. No major cloud has an Ethiopia region today, so data-residency hosting must be
> resolved before any production launch serving Ethiopian users — it is an open decision,
> not solved by this codebase.
