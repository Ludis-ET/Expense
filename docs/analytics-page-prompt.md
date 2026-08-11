# Prompt: design Santim's analytics page

Paste **everything below the line** into a fresh session. It is self-contained it
carries the data model and the domain rules, so the session does not need to read
the repo to answer well. Nothing about the current analytics or dashboard screens is
included on purpose: this is a clean-sheet brief.

---

You are designing the analytics page for **Santim**, a personal income-and-expense
tracker built for Ethiopian users (ETB first, Telebirr/CBE-style wallets, optional
Ethiopian calendar). Single user per account, with optional household sharing.

I am rebuilding this page from scratch. **Do not give me a list of charts.** Give me
a considered plan for a page that changes what someone does with their money next
month. Assume the reader is one person looking at their own life, not an analyst
looking at a business.

## The data you have

Everything below already exists and is queryable per user. Money is
`Decimal(14,2)`, serialized as strings. Amounts are **always positive** `kind`
carries the sign.

**Account** `name`, `type` (CASH | BANK | MOBILE_MONEY | CARD | OTHER),
`currency`, `openingBalance`, `isShared`, `archived`.

**Category** `name`, `kind` (INCOME | EXPENSE), `icon`, `color`, `archived`.
Unique per `(user, name, kind)`. Users start with ~54 seeded ones (16 income,
38 expense) and can add their own.

**Transaction** `kind` (INCOME | EXPENSE | TRANSFER), `amount`, `currency`,
`date`, `accountId`, `transferAccountId` (transfers only), `categoryId` (**null for
transfers**), `budgetId` + `budgetCycle` (when paid out of a plan), `payee`,
`note`, `tags[]`, `receiptUrl`, `recurringRuleId`.

**RecurringRule** `name`, `kind`, `amount`, `frequency` (DAILY | WEEKLY | MONTHLY
| YEARLY), `interval`, `dayOfMonth`, `nextRun`, `endDate`, `autoPost` (false =
remind only), `active`, `lastRunAt`. Posts real transactions when due.

**Budget** (the user calls these _plans_) `name`, `kind` (ONE_TIME | RECURRING |
UNPLANNED), `plannedAmount`, `cycleOpeningPlanned`, `recurrenceUnit` (HOUR…YEAR) ×
`recurrenceInterval`, `alertThreshold` (%), `state` (ACTIVE | CLOSED), `startsAt`,
`cycleIndex`, `cycleStartedAt`, `nextResetAt`, `endDate`, optional `categoryId`.

**BudgetAllocation** money moving between an account and a plan's pot: `FUND`
(positive) or `RELEASE` (negative), with `accountId`, `cycleIndex`, `date`.

**BudgetAdjustment** a signed change to what a plan is _meant_ to hold, with
`cycleIndex`, `reason`, `date`.

**BudgetCycle** a finished period of a recurring plan: `label`, `startedAt`,
`endedAt`, `openingPlanned`, `adjustedAmount`, `plannedAmount`, `carriedIn`,
`fundedAmount`, `spentAmount`, `leftoverAmount`, `txCount`.

**LedgerEntry** + **LedgerPayment** personal IOUs: `kind` (LENT | BORROWED |
EXPECTED_IN | EXPECTED_OUT), `counterparty`, `totalAmount`, `dueDate`, `status`
(OPEN | SETTLED | CANCELLED), `settledAt`, and part-payments.

**WishlistItem** things wanted but not yet acted on: `name`, `priority` (1 = now
… 5 = someday), `status` (WANTING | PLANNED | BOUGHT | DROPPED), optional
`budgetId`, `plannedAt`, `boughtAt`.

**WeekSnapshot** frozen Sunday-boundary week: `income`, `expense`, `net`,
`avgDailySpend`, `txCount`, `topCategory` (+ amount), `sealed`. Only the current
and previous week are kept.

**ExchangeRate** user-defined `from → to` rates. **User** `currency`, `locale`,
`calendar` (gregorian | ethiopian), `firstDayOfWeek`.

## The rules that make this domain interesting

These are the non-obvious mechanics. A plan that ignores them will produce numbers
that are quietly wrong, and a plan that uses them well will say things no generic
budgeting app can say.

1. **Filling a plan is not a transaction.** The cash stays physically in the
   account; it just stops counting as available.
   `pot = Σ allocations − Σ plan expenses`, and
   `account available = real balance − Σ(allocations from it) + Σ(plan expenses charged to it)`.
2. **Spending from a plan** writes an ordinary EXPENSE carrying `budgetId`: the real
   balance drops **and** the reservation frees in the same moment. Nothing is
   double-counted.
3. **UNPLANNED** is a built-in plan with no pot. It labels spending that was never
   reserved for. It must be excluded from every reservation aggregate but the
   share of spending that lands in it is itself one of the most telling numbers on
   the page.
4. **Recurring cycles roll lazily** at read time. Leftover money carries into the
   next cycle by construction (the pot is cumulative). Cycles where nothing moved
   are skipped, not stored so cycle history has gaps by design.
5. **A plan's amount is versioned, not edited.** `openingPlanned + adjustments =
plannedAmount`. Each cycle keeps the figure it opened with, so "what did I plan
   for March, and what did I change mid-month" are both answerable.
6. **Transfers have no category** and must never be counted as income or expense  
   they move money between the user's own accounts.
7. **Currencies never mix without an explicit rate.** Treat each currency as its own
   world unless a rate exists; say so when a total is incomplete rather than
   silently under-reporting.
8. Dates may be shown in the **Ethiopian calendar**, weeks may start Sunday or
   Monday, and everything is stored UTC.

## What I want from you

Design the page. Specifically:

1. **A point of view.** What is this page _for_? State the two or three questions it
   exists to answer, and let everything else earn its place against them. Say
   explicitly what you are leaving out and why.
2. **Structure.** The order things appear in, and what the eye should land on first,
   second, third. Justify the hierarchy what makes the top-most thing top-most.
3. **Every metric, derived precisely.** For each number or chart: the exact
   computation from the fields above (which models, which filters, which date
   window, how transfers and UNPLANNED are handled), and more importantly _what
   a person does differently_ after reading it. Kill any metric that fails that
   second test.
4. **At least three things a generic budgeting app could not show**, built from the
   mechanics in the previous section: reservation vs. availability, plan adherence
   against the figure a cycle _opened_ with, carry-over behaviour across cycles,
   unplanned share of spending, the wishlist funnel (wanting → planned → bought,
   and how long that takes), IOU exposure and who is slow to pay, recurring
   commitments as a fixed floor under discretionary spending. Pick the ones that
   earn their place; invent better ones if you can.
5. **Form for each thing.** Chart type, or deliberately not a chart a sentence, a
   single number, a comparison, a small table. Justify each choice; default to the
   simplest form that carries the meaning. Say what the empty and single-data-point
   states look like.
6. **Time and scope controls.** What ranges are offered, what the default is and
   why, how currency scoping is surfaced, and what happens to a comparison when the
   previous period has no data.
7. **Honesty rules.** Where the page must admit it doesn't know: missing exchange
   rates, a month still in progress, a plan that started mid-period, too little
   history for a trend. Specify the wording pattern for these.

## Constraints

- Read-only page. It may deep-link into transactions, accounts or a plan, but it
  does not edit anything.
- Mobile is the primary target. Assume a 360px-wide screen first; the desktop
  layout is the adaptation, not the other way round.
- Light and dark themes both matter. Colour must never be the only carrier of
  meaning.
- A brand-new user with four transactions and no plans must see something useful,
  not a wall of zeroes. Design that state deliberately.
- Prefer fewer, better things. If the page has more than about eight distinct
  elements, argue for each one or cut it.

## Output format

Markdown. Open with the point of view in under 120 words, then a top-to-bottom
walkthrough of the page. For each element give: **name**, **what it answers**,
**exact derivation**, **form**, **empty state**, and **the decision it drives**.
Close with an explicit "deliberately excluded" list and your reasoning.

Be opinionated. Where you are unsure, commit to a recommendation and say what would
change your mind. I would rather argue with a strong plan than assemble a weak one.
