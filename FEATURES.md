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

- Choose **one-time** or **recurring**, and say how much you **plan to spend**. That figure is also the ceiling on how much money the plan will accept.
- **Any cadence you like.** Recurring plans repeat *every N* hours, days, weeks, months, quarters or years - one tap for the common ones (daily, weekly, fortnightly, monthly, quarterly, yearly), or dial in something like "every 6 hours" or "every 10 days".
- **You pick the start date.** A plan does not silently begin the moment you create it: set when it starts, and it is marked *Scheduled* until then. You can fill it in advance, but nothing can be spent from it early.
- A new plan starts **empty**. You fill it from your accounts - this is *not* a transaction, it is a reservation: the cash stays physically in the account but stops counting as available anywhere in Santim (accounts page, dashboard, the overdraw guard). This is also how you ring-fence money you refuse to touch - rent, fees, an emergency buffer.
- **Give back** any unspent money to the account it came from at any time.

### Unplanned - the built-in catch-all

Every account has one plan it did not create: **Unplanned**, pinned to the top of the Plans tab and impossible to delete, close or fund.

It is where spending goes when you never set money aside for it. It has **no pot of its own** - each expense comes straight out of whichever account you choose, from whatever is genuinely free after your other plans have taken their share. Pick it in the "Pay from" dropdown and a second dropdown appears asking which account the money actually leaves.

Because expenses are always filed against a plan, Unplanned is also the way to spend straight from an account: pick it, then say which account. It behaves like any other plan everywhere else: its own detail page, its own searchable transaction history, and a running total of how much slipped through unplanned. Watching that number is the point - a recurring expense showing up there is a plan waiting to be made.

### Spending from a plan

On the transaction form, the "Pay from" dropdown lists **plans, not accounts** - every expense belongs to one. It shows any plan that still holds money, plus Unplanned. Pick a plan and:

- its category is auto-selected (if it has one),
- the expense comes out of the plan's pot **and** the real account balance at the same moment, so nothing is double-counted,
- Santim refuses anything that would take the plan negative.

### Plan detail page (`/budgets/:id`)

Everything about one plan on its own page: what's left, a bar reading spent → still in the pot → not yet filled, which accounts the money is held in, and a **timeline** of recent fills, give-backs and expenses.

Its **transactions** section is built for plans with a lot of history (Unplanned especially): full-text search over payee and note, filters for category, account, cycle and date range, four sort orders, and paging - all resolved on the server, so nothing slows down as the list grows. Click any row for the full detail, edit or delete it in place.

- **One-time plans** close themselves once the pot is empty *and* something has been spent from them. Closed plans stay listed and keep their history, but no longer appear when you add a transaction. **Reopen** them any time.
- **Recurring plans** snapshot each finished cycle - planned, carried in, filled, spent, leftover - then carry any leftover money forward into the new cycle and start accepting fills again. Open a past cycle to load the transactions that were in it. Cycles where nothing happened are skipped rather than stored, so a fast cadence left alone for a week does not bury you in empty records.

### Wishlist

A **dream board** for things you want (phones, trips, gear). Deliberately money-free: a want is just an idea, so writing one down commits nothing.

- Emoji (a large, searchable set), name, priority, an optional link and a note. No cost, no savings.
- **Plan this wish** is how a want becomes real: it asks for the few things a plan needs (how much, one-time or a repeating cadence, start date, optional category and colour), creates a **budget plan**, and links the two. The want flips to **Planned** with a link straight to its plan, which you then fill a little at a time like any other.
- Statuses: wanting, planned, bought, dropped. Marking bought is just a milestone; the actual spending happens through the plan.
- Click any want for a **detail view** with everything on it: the note, the link, its plan and what that plan is for, plus every action (edit, plan, unlink, drop, mark bought, delete).
- Search across names and notes, filter by status or priority, and sort by priority, date or name. Tab counts cover the whole list, so they stay put while you search.

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

## Android app & bank-SMS capture

A Flutter client (`mobile/`) covering the dashboard, activity, plans, wallets and settings — plus the one thing only a phone can do: reading your bank's SMS so you stop typing transactions.

**How it works.** A native broadcast receiver catches messages from the banks you approve, the moment they arrive — app closed, swiped away, phone locked. Each message is queued in an on-device outbox and uploaded by a background worker with retry and backoff, so a dead zone delays a transaction rather than losing it. The server pulls out the amount, direction, balance, counterparty and reference number, scores how much it understood, and puts a draft in your **message inbox**. You glance at it and tap once.

**Setup** is six steps: allow SMS, pair the phone, pick your banks, say which wallet holds cash, optionally import history, and lift Android's battery restrictions. The bank picker — **Messaging points** — lists the senders actually in your inbox with a sample message, since sender IDs vary by carrier. You can also add one by hand, link each to a wallet and a default category, and attach the wallet's account number.

**The swipe deck.** *Review all* opens a full-screen stack, one message per card. Swipe right to record, left to skip; verdict stamps fade in as you drag and the next card peeks out underneath. Anything the parser could not work out is a highlighted chip on the card — tap, pick, carry on. A missing field blocks the swipe and says what it needs rather than half-committing. A month's messages take about a minute.

**It knows what isn't spending.** Cash out of an ATM has not left your net worth — it moved from the bank into your pocket — so Santim offers it as a transfer into your cash wallet instead of double-counting it when you spend the cash. Money sent to another account is matched against your wallets' account numbers: if it is one of yours, it becomes a transfer; if not, it stays an expense. Neither can ever auto-post, because both need a destination the parser cannot know.

**Importing history.** Live capture starts when setup finishes. Anything older comes in via a date range you choose — presets from 30 days to everything, or a custom range, with a count shown before you commit. Re-importing an overlapping range is harmless: the phone de-duplicates locally and the server fingerprints every message.

**Review by default.** Nothing reaches your ledger unseen. Per sender you can turn on *Record without asking*, which needs a mapped wallet, a default category, and a confident read — and the write still goes through the same overdraw guard as a hand-typed entry, so a refusal shows up as an explanation instead of a silent failure.

**When a parse is wrong.** Every field is editable, the original SMS is one tap away, and *Always use these* teaches the sender its wallet and category. Raw message text is kept, so improving a bank's pattern lets you re-read stored messages rather than re-uploading them.

Because Google restricts SMS permissions to a short list of approved use cases that expense tracking is not on, the app installs directly (`flutter build apk` → `adb install`) rather than through Play. See [`mobile/README.md`](mobile/README.md).

---

## Starter categories

New accounts (and the demo) begin with a rich default set you can fully customize:

- **Income:** Salary, Freelance, Business, Gift Received, Other Income
- **Expense:** Food & Groceries, Transport, Rent, Utilities, Airtime & Data, Health, Education, Entertainment, Shopping, Gifts, Family Support, Subscriptions, **Unnecessary** (impulse buys), Other

## Not built (by design)

Deliberately out of scope for now: direct bank-API sync (no open-banking rails to plug into here) and receipt-image OCR. **Multi-currency** is supported per wallet with manual exchange rates and per-currency dashboard/analytics views (amounts are never naively merged). **Installable PWA** (Add to Home screen on Android and iOS) is supported.

**Automatic transaction import** now exists on Android via bank-SMS capture — see above. It is not available on iOS and cannot be: Apple gives third-party apps no access to Messages at all. The Android app is distributed by direct install, not through Play.
