# ResearchTracker — Feature Guide

A walkthrough of everything you can do in the app, organized by page. Every record
belongs to one organization (`orgId`) — you only ever see your own org's data.

## Getting in

### Register / Login (`/register`, `/login`)
Create an account (becomes a `RESEARCHER` by default) or log in with an existing one.
Auth uses a short-lived JWT access token plus a longer-lived refresh token, so you
stay signed in across sessions without re-entering a password constantly.

**Demo account** (after `pnpm db:seed`): `admin@example.com` / `password123`
— org "Addis Ababa University", user "Abebe Bekele" (ADMIN).

### Accept invite (`/accept?token=...`)
If a teammate invites you by email, opening the link shows which org and role
you're joining, then adds you to it once you accept (registering first if you
don't have an account yet).

## Roles — what each one can do

| Role | Typical use |
|---|---|
| `ADMIN` | Full control: invite/remove members, manage all projects, approve budgets |
| `PROJECT_LEAD` | Create/manage projects they lead, invite teammates, approve budget items and expenses |
| `FINANCE_OFFICER` | Create/edit budget items, approve or reject expenses — no project-management rights |
| `RESEARCHER` | Default role: work inside projects they're a member of, submit expenses, log ideas |
| `REVIEWER` | Read/review access (project `TeamRole: REVIEWER` also exists at the per-project level) |
| `FUNDER` | External stakeholder role, for future funder-facing reporting |

A separate, per-project **team role** (`PI`, `CO_PI`, `COLLABORATOR`, `REVIEWER`) tracks
someone's position on a specific project, independent of their org-wide role above.

## Dashboard (`/dashboard`)

Your home base after login:
- **Stat cards** — quick counts (active projects, budget health, etc.)
- **Budget donut chart** — SVG breakdown of spend by category
- **Budget gauge** — planned vs. approved spend at a glance
- **Recent projects** and **upcoming milestones** — jump back into active work fast

## Projects (`/projects`)

- **Grid view** with filters (e.g. by status: `PLANNING`, `ACTIVE`, `ON_HOLD`,
  `COMPLETED`, `CANCELLED`)
- **Create Project** modal — spin up a new project in seconds
- Click into a project for a **tabbed detail view**:
  - **Overview** — description, status, timeline
  - **Team** — see/manage members and their team role (PI, Co-PI, Collaborator, Reviewer)
  - **Budget** — this project's budget items and expenses
  - **Milestones** — this project's milestone list

### Milestones (inside a project)
Add a milestone with a description and optional due date. Each milestone has a
status you move through: `PENDING` → `IN_PROGRESS` → `DONE`. Edit or delete as
plans change.

## Budget (`/budget`)

The **org-wide portfolio view** — every project's budget side by side, planned vs.
approved spend, so admins/finance can see the whole picture at once (not just one
project at a time).

**How the money flow works:**
1. An Admin, Project Lead, or Finance Officer creates a **budget item** on a project
   (a category with a planned amount).
2. Any project member can **submit an expense** against that budget item.
3. An Admin, Project Lead, or Finance Officer **approves or rejects** it. Expenses
   sit as `PENDING` until decided, then move to `APPROVED` or `REJECTED`.

This gives you an audit trail — who requested what, who approved it, and how actual
spend compares to plan.

## Ideas (`/ideas`)

A **drag-and-drop Kanban board** for capturing research ideas before they become
full projects. Each idea has a priority and moves through a status: `OPEN` →
`CONVERTED` (turned into a real project) → `CLOSED` (shelved). Great for a team
backlog of "things we might want to research next."

## Insights (`/insights`)

Analytics views that go beyond raw numbers:
- **Burn-rate forecast** — a chart projecting how your budget will deplete over
  time based on current spend
- **Impact metrics** — summary stats on research output/impact
- **Collaboration network graph** — a node-link visualization of who's working
  with whom across your projects, useful for spotting silos or key connectors

## Reports (`/reports`)

AI-assisted writing, grounded in your actual project data (not generic text):
- **Generate a report** for any project — choose **Progress report**, **Funder
  report**, or **Proposal draft**, and the AI pulls real milestones/budget/status
  into a first draft you can edit.
- **Extract** — paste reference text (e.g. a paper abstract or notes) and have AI
  pull out structured information from it.

> Requires an AI provider to be configured first — see Settings below.

## Settings (`/settings`)

- **Profile** — name, ORCID iD (format `0000-0000-0000-0000`)
- **Language** — English / Amharic / Oromo / Tigrinya
- **Theme** — light / dark / system
- **AI Providers** — bring your own API key for **Anthropic, OpenAI, or Google**:
  add a key, pick a model, set a priority order (if one provider fails, the next
  is tried), and test the connection before relying on it. Keys are encrypted at
  rest on the server, never sent back to the browser in plaintext.

## Notifications

A live menu (bell icon) surfaces things needing your attention: new invites,
expenses awaiting your approval, upcoming milestone deadlines, and similar
org activity — so you don't have to go hunting for what changed.

## Team management (Invitations)

Admins and Project Leads can invite new teammates by email with a specific role
attached. Pending invites can be listed or revoked before they're accepted. The
invited person gets a link to `/accept` to join your org directly into that role.

---

## Not yet built (by design)

Per the original scope, these are deliberately deferred: microservice extraction,
Kubernetes/Terraform, Elasticsearch/vector semantic search, live ORCID/CrossRef
integration, full i18n translation (the language *picker* exists, full translated
UI does not), PWA/offline support, and payment gateways (telebirr/Chapa).

**Open question:** Ethiopia's PDPP law requires in-country storage of Ethiopian
personal data, but no major cloud provider has an Ethiopia region yet — production
data-residency hosting is intentionally left unresolved in this codebase.
