# Santim Web Frontend — UI & Feature Brief

Design inventory of the current web app so a new UI can cover **every page, nav link, interaction, and product concept**.

- **Product:** Santim  
- **Codebase:** `frontend/` (Next.js App Router)  
- **Auth shell:** `frontend/src/app/(app)/layout.tsx`  
- **Public:** landing, login, register, offline fallback  

> **Web vs Android:** Full money UI lives on web. Bank SMS capture / inbox is **Android-only** (web only markets it). PWA install, browser app-lock, and service-worker offline are **web-only**.

---

## 1. App flow (high level)

```
Landing (/)
  ├─ Sign in → /login → /dashboard
  └─ Get started → /register → /dashboard

Authenticated shell ((app)/layout)
  ├─ Cash wallet prompt (if cashAccountId missing)
  ├─ Sidebar (desktop) / drawer (mobile)
  ├─ Topbar (search, currency, add, theme, notifications, user menu)
  ├─ Mobile bottom nav + Ask Santim
  ├─ Command palette (⌘K / Ctrl+K)
  ├─ Assistant FAB
  └─ Lock screen (when app lock engaged)

Sign out → clear session → /login
```

**Auth gate:** Unauthenticated visits to `(app)/*` redirect to `/login`.  
**Success after login/register:** `/dashboard`.  
**Demo (landing):** `demo@example.com` / `password123`.

---

## 2. Navigation

### 2.1 Sidebar (desktop + mobile drawer)

File: `frontend/src/components/layout/sidebar.tsx`

| Group | Label | Route | Icon |
|-------|-------|-------|------|
| Overview | Dashboard | `/dashboard` | LayoutDashboard |
| Money | Transactions | `/transactions` | ArrowLeftRight |
| Money | Accounts | `/accounts` | Wallet |
| Insights | Analytics | `/analytics` | BarChart3 |
| Insights | Guides | `/guides` | BookOpen |
| Plan | Budgets & Wishes | `/budgets` | PiggyBank |
| Plan | Money Tab | `/tab` | HandCoins |
| Bottom | Settings | `/settings` | Settings |

**Footer:** brand, user avatar, name, email.

**Not in sidebar (reached other ways):**

- Wishlist → `/budgets?tab=wishlist`
- Recurring → `/transactions?tab=recurring` (also `/recurring` redirects here)
- Assistant → FAB / Ask Santim (`/assistant` redirects to `/dashboard?assistant=1`)

### 2.2 Mobile bottom nav

File: `frontend/src/components/layout/mobile-bottom-nav.tsx`

| # | Label | Route | Notes |
|---|-------|-------|-------|
| 1 | Home | `/dashboard` | |
| 2 | Activity | `/transactions` | |
| 3 | Add | `/transactions?add=1` | Accent FAB — opens add form |
| 4 | Wallets | `/accounts` | |
| 5 | Plan | `/budgets` | |

Below tabs: full-width **Ask Santim**.

### 2.3 Topbar actions

File: `frontend/src/components/layout/topbar.tsx`

| Control | What it does |
|---------|----------------|
| Hamburger | Open sidebar (mobile) |
| Search chip / icon | Open command palette |
| Currency selector | Switch display currency |
| Ask Santim | Open AI assistant (smaller breakpoints) |
| Download App | PWA / APK install promo |
| Add | → `/transactions?add=1` |
| Hide amounts | Toggle money visibility |
| Sync status | Offline / outbox indicator |
| Theme toggle | Light / dark / system |
| Notifications bell | Dropdown of alerts |
| User menu | Ask Santim, Lock / Set up lock, Sign out |

### 2.4 Command palette (⌘K)

File: `frontend/src/components/command-palette.tsx`

- Add transaction  
- Go to: Dashboard, Transactions, Recurring rules, Accounts, Budgets, Wishlist, Money Tab, Analytics, Settings  
- Ask about your money  
- Couples & shared accounts (household)  
- App lock settings / Lock Santim now  
- Toggle theme  

---

## 3. Routes & pages (every screen)

### Public

| Route | File | Need / purpose |
|-------|------|----------------|
| `/` | `app/page.tsx` | Marketing landing: hero, features, Android SMS pitch, ETB/local, CTAs, theme, install |
| `/login` | `app/login/page.tsx` | Email + password → dashboard |
| `/register` | `app/register/page.tsx` | Name + email + password (min 8) → dashboard |
| `/~offline` | `app/~offline/page.tsx` | PWA offline fallback |

### Authenticated

| Route | File | Need / purpose |
|-------|------|----------------|
| `/dashboard` | `(app)/dashboard/page.tsx` | Home overview: available to spend, health, insights, recent activity, plans |
| `/transactions` | `(app)/transactions/page.tsx` | Ledger + Recurring tabs; filters; add/transfer/import |
| `/accounts` | `(app)/accounts/page.tsx` | Wallets list; available vs locked; transfer/add |
| `/budgets` | `(app)/budgets/page.tsx` | Plans + Wishlist tabs |
| `/budgets/[id]` | `(app)/budgets/[id]/page.tsx` | Single plan detail (fund/release/adjust/close) |
| `/analytics` | `(app)/analytics/page.tsx` | Deep money insights (read-only + deep links) |
| `/guides` | `(app)/guides/page.tsx` | Educational articles |
| `/tab` | `(app)/tab/page.tsx` | Money Tab / IOUs / expected cash |
| `/settings` | `(app)/settings/page.tsx` | Profile, lock, rates, household, categories, AI |
| `/assistant` | redirect | → `/dashboard?assistant=1` |
| `/recurring` | redirect | → `/transactions?tab=recurring` |

---

## 4. Page-by-page interactions

### 4.1 Landing `/`

- Nav anchors: Features, Android app, Made local, Get started  
- CTAs: Start free, Live demo, Sign in  
- Theme toggle; app download  
- Feature cards: Income & expenses, Budgets, Savings, Recurring, Analytics, AI assistant  
- Android showcase (SMS capture pitch)  

### 4.2 Login / Register

| | Login | Register |
|---|-------|----------|
| Fields | Email, Password | Name, Email, Password |
| CTA | Sign in | Create account |
| Alt link | Create one → register | Sign in → login |

Errors via toast. Success → `/dashboard`.

### 4.3 Dashboard `/dashboard`

**Need:** Answer “what can I spend?” and surface risks / upcoming money.

**Sections (current):**

1. Header + currency badge  
2. **HeroBalance** — greeting, Gregorian + Geʿez date, **Available to spend**, real vs set-aside, Income / Spent / Saved %  
3. Financial health  
4. Smart insight (rule-based copy)  
5. Weekly snapshot, spending streaks, Tab widget, Wishlist widget  
6. Family support tracker, category heat alerts  
7. Household widget  
8. Mini stats: Net this month, Avg daily spend, Unnecessary, Upcoming bills  
9. Spending pace  
10. Recent transactions + budget plans + set-aside  
11. Upcoming recurring (7 days)  
12. Link to full analytics  

**Empty states:** no transactions / no plans.  
**Loading:** skeletons.  
**Deep links:** open transaction detail; jump to budgets / tab / wishlist.

> Note: `QuickActions` and `DashboardAnalytics` components exist but are **not mounted** on the current dashboard.

### 4.4 Transactions `/transactions`

**Tabs:** Ledger | Recurring (`?tab=recurring`)

**Ledger interactions:**

- **Add** (`?add=1` or shortcut `n`) → TransactionForm modal  
- **Transfer** → TransferModal  
- **Export / Import** → ExportImportModal  
- Filters: month navigator, search (payee/note), type (All / Expense / Income / Transfer), category, plan (`?budgetId=`)  
- Daily pace chart  
- Row click → TransactionDetailModal (view / edit / delete)  
- Offline outbox rows merged into list (pending / syncing / error)  
- Pagination  

**Transaction form fields:**

- Kind: Expense / Income  
- Amount  
- Pay from: plan (incl. Unplanned) or account (income)  
- Draw from account  
- Release-from (multi-funder when applicable)  
- Category (+ AI suggest)  
- Date, Payee, Note, Tags  

**Recurring tab:** list rules, toggle active, run now, create/edit/delete rule modal (`autoPost`, schedule, etc.).

### 4.5 Accounts `/accounts`

**Need:** Manage wallets and see free vs held money.

- Summary: **Available to spend**; real vs locked in plans  
- Actions: Transfer, Add account  
- Card: name, type, currency, available, locked, 14-day sparkline, Edit, Delete  
- Card click → AccountDetailModal (recent txs, plan pots)  

**Account form:** name, type (`CASH` | `BANK` | `MOBILE_MONEY` | `CARD` | `OTHER`), currency, opening balance, icon, color.

### 4.6 Budgets & Wishes `/budgets`

**Tabs:** Plans | Wishlist (`?tab=wishlist`)

#### Plans

- Copy framing: envelopes you fill, then spend from  
- New plan → BudgetPlanForm  
- Search + filters: Status (Active / Closed / All), Type (One-time / Recurring), Sort  
- Totals: locked right now, filled this cycle, spent from plans, spent unplanned  
- Always show built-in **Unplanned** (unless filtering closed)  
- Card click → `/budgets/[id]`  

**BudgetPlanForm fields:** name, kind/recurrence, plan to spend, category, icon, colour, warn-at %, stop after, note.

#### Wishlist

- Statuses: WANTING | PLANNED | BOUGHT | DROPPED  
- Sort: Priority / Newest / Oldest / A–Z  
- Modals: WishForm, PlanWishModal, WishDetailModal  

### 4.7 Plan detail `/budgets/[id]`

**Normal plan actions:** Fund, Release, Adjust (raise/cut), Edit, Close / Reopen, Delete  

**Unplanned:** read-focused (no pot).

**Sections:** Planned / Filled / Spent / Lifetime; money held per account; cycle or transaction list; recent movements.

**Modals:** BudgetPlanForm, FundPlanModal, AdjustPlanModal, TransactionDetailModal, TransactionForm.

### 4.8 Analytics `/analytics`

**Framing:** means, where money went, free to spend — mostly read-only with deep links.

**Tabs:** Overview | Trends | Categories | Calendar | Seasons  

**Overview themes:** cash flow; planned vs unplanned; reserved vs available; plan discipline; commitments (fixed floor); wishlist; ledger/IOUs.

### 4.9 Guides `/guides`

Educational content by category (Getting started, Saving, Spending, Debt). Suggestions + guide reader modal. Web-primary.

### 4.10 Money Tab `/tab`

**Need:** Track IOUs and expected in/out (cash-flow commitments that aren’t yet ledger).

- Forecast banner  
- Stats: Net position, Owed to you, Incoming, You owe, Outgoing  
- Views: By entry | By person  
- Filters: All open, They owe me (LENT), I owe (BORROWED), Incoming (EXPECTED_IN), Outgoing (EXPECTED_OUT)  
- New entry; settle/pay; detail modal; delete  

**Form fields:** Type, Person/source, Label, Amount, Expected by, Category, Account (when recording money now), Note.

### 4.11 Settings `/settings`

Scroll sections + mobile chips / desktop rail. Hash deep-links (e.g. `#security`, `#app-lock` → security).

| Section id | Nav label | Contents & interactions |
|------------|-----------|-------------------------|
| `profile` | Profile | Banner hero; AvatarPicker; BannerPicker; name; default currency (ETB/USD/EUR/GBP/KES/AED); language (en/am/om/ti); first day of week; calendar Gregorian / Ethiopian; Save |
| `appearance` | Appearance | Theme: Light / Dark / System |
| `security` | Security | App lock: set PIN, auto-lock interval, biometrics, change PIN, disable, lock now |
| `currencies` | Currencies | Manual exchange rates: list / add / delete |
| `household` | Household | Create household, invite by email, accept pending, share account checkboxes, leave |
| `categories` | Categories | Income/Expense CRUD; icon/color; delete + reassign |
| `ai` | Assistant | Anthropic / OpenAI / Google: enable, model, API key, reorder, test, save |

---

## 5. Global overlays & shared interactions

| Component | When it appears | User need |
|-----------|-----------------|-----------|
| **CashWalletPrompt** | After login if `cashAccountId` null | Pick or create cash wallet (ATM → cash, not spending) |
| **TransactionForm** | Add/edit money in/out | Record expense/income correctly against account + plan |
| **TransferModal** | Move between wallets | Internal transfer |
| **TransactionDetailModal** | Tap a transaction | Inspect / edit / delete |
| **AccountDetailModal** | Tap a wallet | Wallet history + pots |
| **ExportImportModal** | Transactions toolbar | CSV export/import |
| **Budget / Wish / Ledger modals** | Plans, wishlist, Money Tab | Domain CRUD |
| **ConfirmDialog** | Destructive actions | Confirm delete/close/etc. |
| **AssistantFab / AskWidget** | FAB or Ask Santim | Ask questions; monthly review (BYO API keys) |
| **LockScreen** | App lock engaged | PIN / biometric unlock |
| **Notifications menu** | Topbar bell | Read / mark all; types include budget_*, wishlist_*, recurring_due |
| **Install / Android popups** | PWA prompts | Install web app or get Android APK |
| **Splash / AppLoader / PageLoader** | Boot & route loads | Loading chrome |

---

## 6. Product concepts the UI must preserve

These are the mental model — redesign can restyle, but should not confuse:

| Concept | How the UI talks about it |
|---------|---------------------------|
| **Available to spend** | Real balances minus plan reservations |
| **Real balance** | Money physically in wallets |
| **Locked / set aside** | Money reserved by budget plans |
| **Unplanned** | Built-in catch-all; labels spending with no pot |
| **Funded / filled** | Money put into a plan this cycle (incl. carry-over) |
| **Plan health** | unplanned, scheduled, empty, partly-funded, ready, spending, low, drained, closed |
| **Draw from vs release from** | Spend from a pot held in one account while paying from another |
| **Unnecessary / impulse** | Insight + analytics |
| **Family support** | Category-driven tracker |
| **Money Tab forecast** | Net if due IOUs/expectations settle |
| **Fixed floor / commitments** | Recurring obligations in analytics |
| **Currency scope** | Header currency filter; incomplete rates honesty |
| **Pending sync** | Offline outbox on transactions |
| **Cash wallet** | Designated wallet for ATM cash withdrawals |

---

## 7. Feature checklist (for new UI coverage)

Use as a design QA list:

### Core money
- [ ] Dashboard overview (available / real / locked)
- [ ] Transaction ledger (filter, paginate, detail)
- [ ] Add expense / income
- [ ] Transfer between accounts
- [ ] Export / import CSV
- [ ] Offline / pending sync indication
- [ ] Accounts CRUD + detail
- [ ] Categories CRUD + reassign

### Plans & wishes
- [ ] Budget plans list + Unplanned
- [ ] Plan detail (fund / release / adjust / close / reopen / delete)
- [ ] Wishlist lifecycle (want → plan → bought / dropped)

### Commitments & people
- [ ] Recurring rules (CRUD, toggle, run now)
- [ ] Money Tab IOUs / expected (CRUD, settle, by person)
- [ ] Household (create, invite, share accounts, leave)

### Insights
- [ ] Analytics tabs (overview, trends, categories, calendar, seasons)
- [ ] Guides reader
- [ ] Notifications inbox

### Identity & prefs
- [ ] Profile (avatar, banner, currency, language, calendar, week start)
- [ ] Theme
- [ ] App lock (PIN / biometric / auto-lock)
- [ ] Exchange rates
- [ ] AI providers (keys, models, ask + review)

### Chrome & motion
- [ ] Sidebar + mobile bottom nav + topbar
- [ ] Command palette
- [ ] Cash wallet first-run prompt
- [ ] Auth (login / register / logout)
- [ ] Landing + install / Android marketing
- [ ] Offline fallback page

### Explicitly out of web UI (Android)
- [ ] SMS capture setup
- [ ] Message inbox / review deck
- [ ] Native permission & upload queue

---

## 8. API surfaces the UI depends on

| Domain | Endpoints (shape) |
|--------|-------------------|
| Auth / user | `POST /auth/login`, `/auth/register`, `GET/PUT /users/me`, presets for avatars/banners |
| Dashboard | `GET /dashboard` |
| Accounts | `GET/POST /accounts`, `PUT/DELETE /accounts/:id` |
| Transactions | `GET/POST /transactions`, `PUT/DELETE /transactions/:id` |
| Budgets | `GET /budgets`, `GET /budgets/:id`, fund/release/adjust/close/reopen, CRUD |
| Wishlist | `GET/POST /wishlist`, plan/status actions |
| Ledger (Tab) | `GET /ledger`, people, summary, payments, CRUD |
| Recurring | `GET/POST /recurring`, run-now, CRUD |
| Categories | `GET/POST /categories`, `PUT/DELETE` |
| Analytics | `/analytics/page`, series, categories, heatmap, payees, seasonal, movers, … |
| Notifications | `GET /notifications`, read, read-all |
| Household | create, invite, accept, leave, share account |
| Exchange rates | `GET/PUT /exchange-rates`, delete |
| AI | settings, test, ask, review, categorize |
| Guides | `GET /guides` |

---

## 9. Key source files

```
frontend/src/app/layout.tsx
frontend/src/app/page.tsx
frontend/src/app/login/page.tsx
frontend/src/app/register/page.tsx
frontend/src/app/(app)/layout.tsx
frontend/src/app/(app)/dashboard/page.tsx
frontend/src/app/(app)/transactions/page.tsx
frontend/src/app/(app)/accounts/page.tsx
frontend/src/app/(app)/budgets/page.tsx
frontend/src/app/(app)/budgets/[id]/page.tsx
frontend/src/app/(app)/analytics/page.tsx
frontend/src/app/(app)/guides/page.tsx
frontend/src/app/(app)/tab/page.tsx
frontend/src/app/(app)/settings/page.tsx
frontend/src/components/layout/sidebar.tsx
frontend/src/components/layout/topbar.tsx
frontend/src/components/layout/mobile-bottom-nav.tsx
frontend/src/components/layout/notifications-menu.tsx
frontend/src/components/command-palette.tsx
frontend/src/components/finance/cash-wallet-prompt.tsx
frontend/src/lib/auth.tsx
frontend/src/lib/types.ts
```

---

## 10. Navigation map (quick copy)

```
Sidebar
├── Overview
│   └── Dashboard              → /dashboard
├── Money
│   ├── Transactions           → /transactions
│   └── Accounts               → /accounts
├── Insights
│   ├── Analytics              → /analytics
│   └── Guides                 → /guides
├── Plan
│   ├── Budgets & Wishes       → /budgets
│   │     ├── Plans            → ?tab=plans
│   │     └── Wishlist         → ?tab=wishlist
│   └── Money Tab              → /tab
└── Settings                   → /settings
      ├── Profile
      ├── Appearance
      ├── Security (app lock)
      ├── Currencies
      ├── Household
      ├── Categories
      └── Assistant (AI)

Mobile: Home | Activity | Add | Wallets | Plan  (+ Ask Santim)

Also: Recurring → /transactions?tab=recurring
      Assistant → FAB / Ask Santim
```

---

*Generated for a full UI redesign. Prefer keeping product language (Available to spend, Plans as envelopes, Unplanned, Money Tab) even if visual language changes.*
