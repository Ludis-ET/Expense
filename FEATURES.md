# Santim - Feature Guide

A walkthrough of everything you can do, page by page. Santim is a **personal** finance app: every account is completely private - there are no teams, orgs or admins. Sign-in exists only so more than one person can each keep their own separate data.

**Demo login** (after `pnpm db:seed`): `demo@example.com` / `password123` - comes with three accounts and ~3 months of transactions so every screen is alive immediately.

## Getting in

### Register / Login (`/register`, `/login`)
Create an account with just a name, email and password - you immediately get a starter set of categories and a "Cash" account. Auth uses a short-lived access token plus a refresh token, so you stay signed in without re-entering your password constantly. Your data is scoped to you and only you.

## Dashboard (`/dashboard`)

Your money at a glance:
- **Stat cards** - total balance across accounts, income this month, spending this month (with up/down trend vs last month), and net, with average daily spend.
- **Recent transactions** - your latest activity, grouped by day.
- **Top spending** donut - where this month's money went, by category.
- **Budgets at risk** - any category near or over its limit.
- **Goals** - progress bars toward your savings goals.
- **Upcoming & unnecessary** - bills due in the next 7 days, plus how much you've spent on "unnecessary" impulse buys this month.

## Transactions (`/transactions`)

The core ledger - every birr in and out.
- **Add** income or expense via the quick-add modal (the **+ Add transaction** button, the `N` shortcut, or the command palette). Pick a type, amount, account, category (filtered to the right type), date, payee, tags and a note.
- **✨ Suggest** - if you've set an AI key, one click reads your payee/note and picks the best category for you.
- **Filter** by month, type, category, account, tag, or free-text search across payees and notes.
- **Edit or delete** any transaction (always visible on mobile, not hover-only); rows are grouped by day with running subtotals.
- **Transfer** between your accounts from this page (same as Accounts).
- **Export** the current view to CSV.

Three transaction kinds: **income**, **expense**, and **transfer** (moving money between your own accounts - transfers change balances but are excluded from income/expense analytics).

## Accounts (`/accounts`)

Your wallets - **cash, bank, mobile-money (e.g. Telebirr), card or other**.
- Each shows a **computed balance** (opening balance + income − expenses ± transfers).
- Add, edit, archive, or delete accounts (deleting is blocked if it has transactions - archive instead).
- **Transfer** money between accounts in one step.
- Pick an icon and color for each.

## Budgets (`/budgets`)

Set a **monthly spending limit per category** and stay ahead of overspending.
- Progress bars turn amber then red as you approach and cross the limit.
- Set an **alert threshold** (e.g. 80%) - when you cross it, Santim drops a notification.
- A month navigator lets you review any past month; a summary strip shows total budgeted vs spent vs remaining.

## Spend locks (`/locks`)

Protect money you refuse to touch. Locks are **per currency** and stack:
- **Safety floor** - "I can't spend below this." Multiple floors use the **highest** floor.
- **Goal vault** - reserve an amount toward a savings goal.
- **Named reserve** - rent buffer, emergency pot, etc.
- Expenses that would break unlocked balance are **blocked** at create time.

## Wishlist (`/wishlist`)

A creative **dream board** for things you want (phones, trips, gear):
- Priority, emoji, optional product link, and progress toward the cost.
- Optionally link a want to a savings goal.
- Statuses: wanting → saving → bought.

## Goals (`/goals`)

Save towards the things that matter - an emergency fund, a trip, a new laptop.
- Set a **target amount** and an optional **deadline**; Santim tells you **how much per month** you need to save to get there.
- Log **contributions** as you save; the goal marks itself **reached** (with a celebration) when you hit the target.
- Give each goal its own icon and color.

## Recurring (`/recurring`)

Automate money that repeats - salary, rent, subscriptions.
- Choose a frequency (daily/weekly/monthly/yearly), interval, and for monthly rules a day of the month (safely clamped for short months, so "the 31st" still works in February).
- **Auto-post** rules create the transaction automatically on schedule; **remind-only** rules just send you a notification.
- **Run now** posts one occurrence on demand; pause/resume any rule with the active toggle.

Occurrences are materialized lazily whenever you open a money screen, so they're always up to date without a background job server.

## Money Tab (`/tab`)

Track money **between you and other people** - separate from recurring bills and day-to-day transactions.

Three entry types:
- **I lent money** - you gave cash to someone; they still owe you (partial repayments supported).
- **I borrowed** - you owe someone; log payments as you pay back.
- **Incoming (one-off)** - money you expect once (freelance invoice, promised gift, refund…) that is **not** on a recurring schedule.
- **Outgoing (one-off)** - a bill you know is coming once (school fee, repair) - not recurring.

Features:
- **By person view** - all open tabs grouped by person with net balance.
- **Net position** on the dashboard - receivable + incoming − payables − outgoing.
- **Cash-flow forecast** - net if due tabs settle this month.
- **Due-date reminders** - bell notifications 3 days before due or when overdue.
- **AI assistant** - ask who owes you, what's incoming, etc. (uses Tab data).
- **Optional account sync** - matching income/expense in accounts (tagged `tab`).
- **Partial settlements** - record repayments in chunks until the tab is cleared.

New starter categories: **Loan Repayment** (income) and **Debt & Loans** (expense).

## Analytics (`/analytics`)

The deep dive into your habits.
- **Income vs. expense** trend - switch between **daily, weekly and monthly** buckets.
- **Spending by category** donut.
- **Top payees** - who you pay the most.
- **12-month income vs. expense** with your **average savings rate**.
- **Unnecessary spend** meter - this month's impulse buys vs last month.
- **Spending heatmap** - a GitHub-style calendar of daily spend across the year.

## Assistant (`/assistant`)

AI features powered by **your own** provider key (Anthropic / OpenAI / Google - set under Settings):
- **Ask about your money** - natural-language questions ("How much did I spend on transport this month?", "Where is my money leaking?", "Who still owes me money?", "What incoming payments am I waiting on?"), answered from your real data, sometimes with a chart.
- **Monthly review** - generate a personalized written review of any month: income vs spending, category shifts, budget adherence, goal progress, and three concrete suggestions.

Without an AI key everything else in the app works normally; these features simply prompt you to add one.

## Settings (`/settings`)

- **Profile** - name, **default currency**, language (English/Amharic/Oromo/Tigrinya), first day of week, and an optional **Ethiopian (Geʿez) calendar** display.
- **App lock** - optional on-device PIN (4–8 digits) plus biometrics via WebAuthn (Face ID, Touch ID, Windows Hello, Android fingerprint). Auto-lock after idle time and/or when you switch apps. Secrets stay in the browser — never sent to the server. Lock instantly from the top bar.
- **Exchange rates** - set your own conversion rates between currencies (e.g. USD → ETB). Combined totals only appear when every rate is defined; otherwise each currency is shown separately.
- **Appearance** - light / dark / system theme.
- **Category manager** - rename, recolor, re-icon, add or delete your income and expense categories (deleting a used category asks where to move its transactions).
- **AI providers** - add/test/prioritize your Anthropic, OpenAI or Google keys. Keys are encrypted at rest and never sent back to the browser.

## Notifications

A live bell menu surfaces things needing attention: budget-threshold alerts, recurring-bill reminders, and goal-reached celebrations.

## Command palette

Press **⌘K / Ctrl+K** anywhere to jump to any page, add a transaction, or toggle the theme.

---

## Starter categories

New accounts (and the demo) begin with a rich default set you can fully customize:

- **Income:** Salary, Freelance, Business, Gift Received, Other Income
- **Expense:** Food & Groceries, Transport, Rent, Utilities, Airtime & Data, Health, Education, Entertainment, Shopping, Gifts, Family Support, Subscriptions, **Unnecessary** (impulse buys), Other

## Not built (by design)

Deliberately out of scope for now: automatic bank-sync/import and receipt-image OCR. **Multi-currency** is supported per wallet with manual exchange rates and per-currency dashboard/analytics views (amounts are never naively merged). **Installable PWA** (Add to Home screen on Android and iOS) is supported; native App Store / Play Store builds are not.
