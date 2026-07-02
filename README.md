# ResearchTracker

A research-management SaaS — **Express + Prisma backend** and a **Next.js 15 frontend**, in a single pnpm workspace.

```
.
├── backend/    Modular-monolith REST API (Express, Prisma, PostgreSQL)
├── frontend/   Next.js 15 App Router web app (Tailwind v4, SWR)
├── pnpm-workspace.yaml
└── package.json   Workspace scripts
```

## Features

**Backend** — JWT auth (access + refresh), multi-tenant org isolation, RBAC, and modules for
projects, teams, budgets/expenses (with an approval workflow), milestones, ideas, notifications,
and a dashboard-stats aggregator. Zod-validated, pino-logged, fail-fast config.

**Frontend** — a polished, responsive app with:

- Marketing **landing page** with light/dark theme
- **Auth** (login / register) wired to the backend
- **Dashboard** with stat cards, an SVG donut chart, budget gauge, recent projects & upcoming milestones
- **Projects**: filterable grid, create modal, and a tabbed detail view (Overview · Team · Budget · Milestones)
- **Budget** portfolio view across all projects (planned vs. approved spend)
- **Ideas** drag-and-drop Kanban backlog with priorities
- **Settings**: profile, language (English/Amharic/Oromo/Tigrinya), ORCID iD, theme picker
- Live **notifications** menu, command-free global theming, toasts, skeletons, empty states

## Prerequisites

- Node 20+
- pnpm 10+ (`corepack enable` will provide it)
- A PostgreSQL 16 database — the free tier of [Neon](https://neon.tech) works well and needs no local install

## Quick start

```bash
# 1. Install all workspace dependencies
pnpm install

# 2. Backend env + database
cp backend/.env.example backend/.env        # then set DATABASE_URL and JWT_SECRET
pnpm db:migrate                             # creates tables (name it "init")
pnpm db:seed                                # demo org, users, project, budget, ideas

# 3. Frontend env (optional — defaults work)
cp frontend/.env.local.example frontend/.env.local

# 4. Run both apps together
pnpm dev
```

- Frontend → http://localhost:3000
- Backend  → http://localhost:4000 (the frontend proxies `/api/*` to it)

**Demo login:** `admin@example.com` / `password123`

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

## Deliberately deferred

Per the original design review, these remain future phases (the architecture is built to absorb them):
microservice extraction, Kubernetes/Terraform, Elasticsearch/vector semantic search, AI summarization,
ORCID/CrossRef live integration, full i18n translation, PWA/offline, and payment gateways (telebirr/Chapa).

> **Compliance note:** Ethiopia's PDPP requires in-country storage of Ethiopian personal data. No major
> cloud has an Ethiopia region today, so production data-residency hosting is an open decision this
> codebase does not resolve.
