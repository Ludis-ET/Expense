// Curated, provider-agnostic financial-literacy guides plus how-to-use-Santim
// walkthroughs. Static content (no external calls). Suggestion rules in
// guides.service.ts reference these by `id`.

export type GuideCategory = "getting-started" | "saving" | "spending" | "debt";

export interface GuideSection {
  heading: string;
  body: string;
}

export interface Guide {
  id: string;
  title: string;
  emoji: string;
  category: GuideCategory;
  readMins: number;
  tagline: string;
  /** Optional deep link into the feature this guide is about. */
  href?: string;
  sections: GuideSection[];
}

export const GUIDES: Guide[] = [
  {
    id: "getting-started",
    title: "Getting started with Santim",
    emoji: "🚀",
    category: "getting-started",
    readMins: 4,
    tagline:
      "A five-minute tour of every part of the app and the order to set it up.",
    href: "/dashboard",
    sections: [
      {
        heading: "1. Add your accounts",
        body: "Start on the Accounts page and add every place you keep money   cash, bank, and mobile money (Telebirr, CBE Birr). Set each opening balance to what you actually hold today. Every balance in Santim is computed from this starting point plus your transactions, so getting it right once means it stays right forever.",
      },
      {
        heading: "2. Log income and expenses",
        body: "Use the Transactions page (or press N anywhere) to record money in and out. Pick a category so your analytics mean something. Transfers move money between your own accounts and never count as spending. Santim now blocks an expense or transfer that would push an account below zero   a gentle guardrail against overdrawing.",
      },
      {
        heading: "3. Create budget plans",
        body: "A budget plan is a named envelope: you decide how much you plan to spend, then fill it from your accounts. That money is set aside immediately   it stops counting as available anywhere in Santim   and can only be spent against that plan. Plans can run once or renew every week, month, quarter or year.",
      },
      {
        heading: "4. Protect and plan",
        body: "Filling a plan is what ring-fences money you refuse to touch - rent, school fees, an emergency buffer. The Wishlist, a tab under Budgets, parks the things you want; when you are ready to act on one, plan it and it becomes a budget plan you can fill over time. Recurring turns bills and income into an automatic habit.",
      },
    ],
  },
  {
    id: "50-30-20",
    title: "The 50/30/20 rule",
    emoji: "⚖️",
    category: "saving",
    readMins: 3,
    tagline: "A simple, globally-used split for needs, wants, and savings.",
    href: "/budgets",
    sections: [
      {
        heading: "The split",
        body: "Of your take-home income, aim to spend about 50% on needs (housing, food, transport, utilities), 30% on wants (eating out, entertainment, subscriptions), and put 20% toward savings and debt repayment. It is a starting frame, not a law   adjust the ratios to your reality.",
      },
      {
        heading: "Make it real in Santim",
        body: "Tag your categories mentally as need or want, then set category budgets that add up to roughly half your income for needs and a third for wants. Your monthly summary shows the leftover   that is your 20%. If needs eat more than half, that is the signal to hunt for a cheaper fixed cost, not to skip saving.",
      },
      {
        heading: "Pay yourself first",
        body: "The 20% only happens if you move it before you spend. Create a recurring auto-save plan for payday so savings leave the room before wants can claim them.",
      },
    ],
  },
  {
    id: "emergency-fund",
    title: "Build an emergency fund",
    emoji: "🛟",
    category: "saving",
    readMins: 3,
    tagline: "The buffer that turns a crisis into an inconvenience.",
    href: "/locks",
    sections: [
      {
        heading: "Why it comes first",
        body: "Before investing or chasing big goals, build a cushion of 3–6 months of essential expenses. It is what stops a medical bill or a lost income month from becoming debt. Even one month saved changes how a bad week feels.",
      },
      {
        heading: "Start with one month",
        body: "Total your essential monthly spending (rent, food, transport, utilities). That number is your first milestone.",
      },
      {
        heading: "Lock it so it's really there",
        body: "An emergency fund you dip into is not an emergency fund. Create a budget plan for the amount and fill it from your accounts. The money then drops out of every \"available\" figure in Santim and can only be spent against that plan, so it stays intact until a real emergency.",
      },
    ],
  },
  {
    id: "automate-saving",
    title: "Pay yourself first, automatically",
    emoji: "🔁",
    category: "saving",
    readMins: 2,
    tagline: "Willpower is unreliable; automation is not.",
    href: "/recurring",
    sections: [
      {
        heading: "The one habit that compounds",
        body: "People who save consistently rarely have more discipline   they have better defaults. If saving happens automatically on payday, you adapt your spending to what is left instead of trying to save whatever survives the month.",
      },
      {
        heading: "Set an auto-save plan",
        body: 'On the Recurring page, choose "Fund a want", pick an amount and a frequency, and Santim sets the money aside for you every period. For everyday spending, a recurring budget plan does the same job: it renews on schedule and carries any leftover into the next cycle.',
      },
    ],
  },
  {
    id: "curb-impulse",
    title: "Curb impulse spending",
    emoji: "🧠",
    category: "spending",
    readMins: 3,
    tagline: "Beat the buy-now urge without feeling deprived.",
    href: "/budgets?tab=wishlist",
    sections: [
      {
        heading: "The 24-hour rule",
        body: "For any non-essential purchase, wait a day (a week for big ones). Most urges fade. What remains is usually something you genuinely value   and now you can plan for it instead of regretting it.",
      },
      {
        heading: "Park it on your wishlist",
        body: 'Instead of buying, add the item to your Wishlist. It gives the want a home without committing a birr. If it still matters in a week, plan it: that spins up a budget plan you can fill a little at a time, and you buy it once the plan is full.',
      },
      {
        heading: 'Name your "unnecessary" spending',
        body: "Santim tracks spending you flag as unnecessary. Seeing the monthly total is often enough to shrink it. Aim to trim it by a third and redirect that money into a budget plan you care about.",
      },
    ],
  },
  {
    id: "plan-envelopes",
    title: "How budget plans hold money",
    emoji: "✉️",
    category: "spending",
    readMins: 3,
    tagline: "Fill an envelope from your accounts, then spend only from it.",
    href: "/budgets",
    sections: [
      {
        heading: "Filling a plan is not a transaction",
        body: "When you move 2,000 into a plan, nothing has been spent yet. The cash is still physically in your account   Santim just stops counting it as available. Your accounts page shows both figures: the real balance, and what is genuinely free after plans.",
      },
      {
        heading: "Spending draws it down",
        body: "When you add an expense, the account dropdown also lists any plan that still holds money. Pick the plan and the expense comes out of its envelope: the plan balance drops, the real account balance drops, and the reservation is released at the same moment. Santim will not let a plan go negative.",
      },
      {
        heading: "One-time vs recurring",
        body: "A one-time plan closes itself once it is empty and has been spent from   it stays on the Budgets page for the record, and you can reopen it. A recurring plan snapshots each finished cycle, carries any leftover into the next one, and starts accepting fills again.",
      },
    ],
  },
  {
    id: "budget-basics",
    title: "Budgeting that actually sticks",
    emoji: "📊",
    category: "spending",
    readMins: 3,
    tagline: "Zero-based and envelope budgeting, made practical.",
    href: "/budgets",
    sections: [
      {
        heading: "Give every birr a job",
        body: "Zero-based budgeting means your income minus your planned spending and saving equals zero   every birr is assigned before the month starts. It surfaces money that would otherwise leak away unnoticed.",
      },
      {
        heading: "Envelopes for problem categories",
        body: "For categories that always overshoot (eating out, data), a plan is a real cash envelope: when it is empty, you stop. Santim warns you as the pot runs low and blocks anything that would take it negative.",
      },
      {
        heading: "Review weekly, not yearly",
        body: 'A five-minute weekly check on the dashboard beats a painful annual reckoning. Watch the "plans running low" panel and top up or ease off early.',
      },
    ],
  },
  {
    id: "debt-payoff",
    title: "Get out of debt",
    emoji: "🧗",
    category: "debt",
    readMins: 3,
    tagline: "Snowball vs avalanche   and how to track who owes whom.",
    href: "/tab",
    sections: [
      {
        heading: "Snowball vs avalanche",
        body: "The avalanche method pays the highest-interest debt first (mathematically cheapest). The snowball method pays the smallest balance first (psychologically motivating   quick wins build momentum). The best method is the one you will actually stick to.",
      },
      {
        heading: "Track loans on the Money Tab",
        body: "Use the Money Tab to record money you have lent or borrowed and money you expect in or out. Its forecast shows your net position if everything settles on time, so debts never live only in your head.",
      },
      {
        heading: "Free up cash flow first",
        body: "Every category you trim is a birr you can throw at debt. Combine a tight budget with a small emergency buffer so a surprise does not send you back to borrowing.",
      },
    ],
  },
];

export function guideById(id: string): Guide | undefined {
  return GUIDES.find((g) => g.id === id);
}
