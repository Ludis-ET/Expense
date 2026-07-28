# Santim - Feature Guide

A walkthrough of everything you can do, page by page. Santim is a **personal** finance app: every account is completely private - there are no teams, orgs or admins. Sign-in exists only so more than one person can each keep their own separate data.

**Demo login** (after `pnpm db:seed`): `demo@example.com` / `password123` - comes with three accounts and ~3 months of transactions so every screen is alive immediately.

## Getting in

### Register / Login (`/register`, `/login`)

Create an account with just a name, email and password - you immediately get a starter set of categories and a "Cash" account. Auth uses a short-lived access token plus a refresh token, so you stay signed in without re-entering your password constantly. Your data is scoped to you and only you.

## Dashboard (`/dashboard`)

Your money at a glance:

- **Stat cards** - money **available to spend** across accounts (that is, the real balance minus anything set aside in budget plans), income this month, spending this month (with up/down trend vs last month), and net, with average daily spend.
- **Recent transactions** - your latest activity, grouped by day.
- **Top spending** donut - where this month's money went, by category.
- **Budget plans** - what's left in each plan and how much of it you've spent.
- **Set aside** - the running total locked inside your plans, which every balance on the page already excludes.
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

- Each shows two figures: the **available balance** (what you can actually spend) and, when a budget plan is holding some of it, the **real balance** physically in the account plus how much is set aside.
- Add, edit, archive, or delete accounts (deleting is blocked if it has transactions - archive instead).
- **Transfer** money between accounts in one step.
- Pick an icon and color for each.

## Budgets (`/budgets`)

Budgets are **envelopes**, not just limits. The page has two tabs: **Plans** and **Wishlist**.

### Plans

A plan is something you name yourself - "Weekend food", "New laptop", "School fees". A category is **optional**: if you attach one, it is pre-selected whenever you spend from the plan.

- Choose **one-time** or **recurring** (weekly / monthly / quarterly / yearly), and say how much you **plan to spend**. That figure is also the ceiling on how much money the plan will accept.
- A new plan starts **empty**. You fill it from your accounts - this is *not* a transaction, it is a reservation: the cash stays physically in the account but stops counting as available anywhere in Santim (accounts page, dashboard, the overdraw guard). This is also how you ring-fence money you refuse to touch — rent, fees, an emergency buffer.
- **Give back** any unspent money to the account it came from at any time.

### Spending from a plan

On the transaction form, the "Pay from" dropdown lists your accounts **and** any plan that still holds money. Pick a plan and:

- its category is auto-selected (if it has one),
- the expense comes out of the plan's pot **and** the real account balance at the same moment, so nothing is double-counted,
- Santim refuses anything that would take the plan negative.

### Plan detail page (`/budgets/:id`)

Everything about one plan on its own page: what's left, a bar reading spent → still in the pot → not yet filled, which accounts the money is held in, and a **timeline** of every fill, give-back and expense.

- **One-time plans** close themselves once the pot is empty *and* something has been spent from them. Closed plans stay listed and keep their history, but no longer appear when you add a transaction. **Reopen** them any time.
- **Recurring plans** snapshot each finished cycle - planned, carried in, filled, spent, leftover, and the transactions in it - then carry any leftover money forward into the new cycle and start accepting fills again.

### Wishlist

A creative **dream board** for things you want (phones, trips, gear):

- Priority, emoji, optional product link, and progress toward the cost.
- Statuses: wanting → saving → bought.
- Shows "Can afford" once what's left is covered by your genuinely spendable money.

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
- **Monthly review** - generate a personalized written review of any month: income vs spending, category shifts, how your budget plans are holding up, and three concrete suggestions.

Without an AI key everything else in the app works normally; these features simply prompt you to add one.

## Settings (`/settings`)

- **Profile** - name, **default currency**, language (English/Amharic/Oromo/Tigrinya), first day of week, and an optional **Ethiopian (Geʿez) calendar** display.
- **App lock** - optional on-device PIN (4–8 digits) plus biometrics via WebAuthn (Face ID, Touch ID, Windows Hello, Android fingerprint). Auto-lock after idle time and/or when you switch apps. Secrets stay in the browser never sent to the server. Lock instantly from the top bar.
- **Exchange rates** - set your own conversion rates between currencies (e.g. USD → ETB). Combined totals only appear when every rate is defined; otherwise each currency is shown separately.
- **Appearance** - light / dark / system theme.
- **Category manager** - rename, recolor, re-icon, add or delete your income and expense categories (deleting a used category asks where to move its transactions).
- **AI providers** - add/test/prioritize your Anthropic, OpenAI or Google keys. Keys are encrypted at rest and never sent back to the browser.

## Notifications

A live bell menu surfaces things needing attention: budget-plan alerts (running low, auto-closed, new cycle started with money carried over) and recurring-bill reminders.

## Command palette

Press **⌘K / Ctrl+K** anywhere to jump to any page, add a transaction, or toggle the theme.

---

## Starter categories

New accounts (and the demo) begin with a rich default set you can fully customize:

- **Income:** Salary, Freelance, Business, Gift Received, Other Income
- **Expense:** Food & Groceries, Transport, Rent, Utilities, Airtime & Data, Health, Education, Entertainment, Shopping, Gifts, Family Support, Subscriptions, **Unnecessary** (impulse buys), Other

## Not built (by design)

Deliberately out of scope for now: automatic bank-sync/import and receipt-image OCR. **Multi-currency** is supported per wallet with manual exchange rates and per-currency dashboard/analytics views (amounts are never naively merged). **Installable PWA** (Add to Home screen on Android and iOS) is supported; native App Store / Play Store builds are not.
