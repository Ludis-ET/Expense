// Curated, provider-agnostic financial-literacy guides plus how-to-use-Santim
// walkthroughs. Static content (no external calls). Suggestion rules in
// guides.service.ts reference these by `id`.

export type GuideCategory = 'getting-started' | 'saving' | 'spending' | 'debt';

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
    id: 'getting-started',
    title: 'Getting started with Santim',
    emoji: '🚀',
    category: 'getting-started',
    readMins: 4,
    tagline: 'A five-minute tour of every part of the app and the order to set it up.',
    href: '/dashboard',
    sections: [
      {
        heading: '1. Add your accounts',
        body: 'Start on the Accounts page and add every place you keep money — cash, bank, and mobile money (Telebirr, CBE Birr). Set each opening balance to what you actually hold today. Every balance in Santim is computed from this starting point plus your transactions, so getting it right once means it stays right forever.',
      },
      {
        heading: '2. Log income and expenses',
        body: "Use the Transactions page (or press N anywhere) to record money in and out. Pick a category so your analytics mean something. Transfers move money between your own accounts and never count as spending. Santim now blocks an expense or transfer that would push an account below zero — a gentle guardrail against overdrawing.",
      },
      {
        heading: '3. Set budgets and goals',
        body: 'Budgets cap what you spend per category each month and warn you before you blow past them. Goals are the opposite — targets you save toward, like an emergency fund or a trip. Both live under Budgets.',
      },
      {
        heading: '4. Protect and plan',
        body: 'Spend Locks ring-fence money you refuse to touch (a safety floor, a goal vault, a named reserve). The Wishlist parks the things you want and shows when you can actually afford them. Recurring turns any of this into an automatic habit — including auto-save plans that feed a goal or wishlist item every week or month.',
      },
    ],
  },
  {
    id: '50-30-20',
    title: 'The 50/30/20 rule',
    emoji: '⚖️',
    category: 'saving',
    readMins: 3,
    tagline: 'A simple, globally-used split for needs, wants, and savings.',
    href: '/budgets',
    sections: [
      {
        heading: 'The split',
        body: 'Of your take-home income, aim to spend about 50% on needs (housing, food, transport, utilities), 30% on wants (eating out, entertainment, subscriptions), and put 20% toward savings and debt repayment. It is a starting frame, not a law — adjust the ratios to your reality.',
      },
      {
        heading: 'Make it real in Santim',
        body: 'Tag your categories mentally as need or want, then set category budgets that add up to roughly half your income for needs and a third for wants. Your monthly summary shows the leftover — that is your 20%. If needs eat more than half, that is the signal to hunt for a cheaper fixed cost, not to skip saving.',
      },
      {
        heading: 'Pay yourself first',
        body: 'The 20% only happens if you move it before you spend. Create a recurring auto-save plan for payday so savings leave the room before wants can claim them.',
      },
    ],
  },
  {
    id: 'emergency-fund',
    title: 'Build an emergency fund',
    emoji: '🛟',
    category: 'saving',
    readMins: 3,
    tagline: 'The buffer that turns a crisis into an inconvenience.',
    href: '/locks',
    sections: [
      {
        heading: 'Why it comes first',
        body: 'Before investing or chasing big goals, build a cushion of 3–6 months of essential expenses. It is what stops a medical bill or a lost income month from becoming debt. Even one month saved changes how a bad week feels.',
      },
      {
        heading: 'Start with one month',
        body: 'Total your essential monthly spending (rent, food, transport, utilities). That number is your first milestone. Make it a savings Goal and watch the progress bar fill.',
      },
      {
        heading: "Lock it so it's really there",
        body: 'An emergency fund you dip into is not an emergency fund. Add a Safety Floor spend lock for the amount — Santim will then refuse everyday expenses that would eat into it, keeping the buffer intact until a real emergency.',
      },
    ],
  },
  {
    id: 'automate-saving',
    title: 'Pay yourself first, automatically',
    emoji: '🔁',
    category: 'saving',
    readMins: 2,
    tagline: 'Willpower is unreliable; automation is not.',
    href: '/recurring',
    sections: [
      {
        heading: 'The one habit that compounds',
        body: 'People who save consistently rarely have more discipline — they have better defaults. If saving happens automatically on payday, you adapt your spending to what is left instead of trying to save whatever survives the month.',
      },
      {
        heading: 'Set an auto-save plan',
        body: 'On the Recurring page, choose "Save to goal" or "Fund a want", pick an amount and a frequency, and Santim contributes for you every period. Your goal shows a projected finish date, and any linked spend lock grows on its own so the money is reserved the moment it lands.',
      },
    ],
  },
  {
    id: 'curb-impulse',
    title: 'Curb impulse spending',
    emoji: '🧠',
    category: 'spending',
    readMins: 3,
    tagline: 'Beat the buy-now urge without feeling deprived.',
    href: '/wishlist',
    sections: [
      {
        heading: 'The 24-hour rule',
        body: 'For any non-essential purchase, wait a day (a week for big ones). Most urges fade. What remains is usually something you genuinely value — and now you can plan for it instead of regretting it.',
      },
      {
        heading: 'Park it on your wishlist',
        body: 'Instead of buying, add the item to your Wishlist. It gives the want a home, shows the cost, and tracks how close you are. When you can truly afford it, Santim marks it "Can afford" — buy it then, guilt-free.',
      },
      {
        heading: 'Name your "unnecessary" spending',
        body: 'Santim tracks spending you flag as unnecessary. Seeing the monthly total is often enough to shrink it. Aim to trim it by a third and redirect that money to a goal.',
      },
    ],
  },
  {
    id: 'goals-vs-wants',
    title: 'Turn wants into goals',
    emoji: '🎯',
    category: 'saving',
    readMins: 2,
    tagline: 'The bridge from wishful thinking to actually owning it.',
    href: '/wishlist',
    sections: [
      {
        heading: 'A want is a wish; a goal has a plan',
        body: 'A wishlist item says "someday". A goal says "by this date, this much per month". The difference is a plan — and plans are what get funded.',
      },
      {
        heading: 'Promote in one tap',
        body: 'On any wishlist item, choose "To goal". Santim creates the savings goal, carries over what you have saved, can reserve the money with a spend lock, and can even start an auto-save plan to hit it on schedule.',
      },
    ],
  },
  {
    id: 'budget-basics',
    title: 'Budgeting that actually sticks',
    emoji: '📊',
    category: 'spending',
    readMins: 3,
    tagline: 'Zero-based and envelope budgeting, made practical.',
    href: '/budgets',
    sections: [
      {
        heading: 'Give every birr a job',
        body: 'Zero-based budgeting means your income minus your planned spending and saving equals zero — every birr is assigned before the month starts. It surfaces money that would otherwise leak away unnoticed.',
      },
      {
        heading: 'Envelopes for problem categories',
        body: 'For categories that always overshoot (eating out, data), treat the budget like a cash envelope: when it is empty, you stop until next month. Santim warns you as you approach the limit so there are no surprises.',
      },
      {
        heading: 'Review weekly, not yearly',
        body: 'A five-minute weekly check on the dashboard beats a painful annual reckoning. Watch the "budgets at risk" panel and adjust early.',
      },
    ],
  },
  {
    id: 'debt-payoff',
    title: 'Get out of debt',
    emoji: '🧗',
    category: 'debt',
    readMins: 3,
    tagline: 'Snowball vs avalanche — and how to track who owes whom.',
    href: '/tab',
    sections: [
      {
        heading: 'Snowball vs avalanche',
        body: 'The avalanche method pays the highest-interest debt first (mathematically cheapest). The snowball method pays the smallest balance first (psychologically motivating — quick wins build momentum). The best method is the one you will actually stick to.',
      },
      {
        heading: 'Track loans on the Money Tab',
        body: 'Use the Money Tab to record money you have lent or borrowed and money you expect in or out. Its forecast shows your net position if everything settles on time, so debts never live only in your head.',
      },
      {
        heading: 'Free up cash flow first',
        body: 'Every category you trim is a birr you can throw at debt. Combine a tight budget with a small emergency buffer so a surprise does not send you back to borrowing.',
      },
    ],
  },
];

export function guideById(id: string): Guide | undefined {
  return GUIDES.find((g) => g.id === id);
}
