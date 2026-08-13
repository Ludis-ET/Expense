import type { AuthUser } from '../../core/context.js';
import { buildFinanceSnapshot, listUserCategories } from './ai.context.js';
import { parseJson, runChat } from './ai.service.js';
import * as conversations from './ai.conversations.js';

export interface AskResult {
  answer: string;
  chart?: { type: 'bar' | 'donut'; title: string; data: { label: string; value: number }[] };
  provider: string;
  conversationId: string;
  messageId?: string;
}

/** "Ask about your money" - grounded NL Q&A, optionally inside a saved chat. */
export async function ask(
  user: AuthUser,
  question: string,
  opts: { conversationId?: string; persist?: boolean } = {},
): Promise<AskResult> {
  const shouldPersist = Boolean(opts.conversationId || opts.persist);
  const conversation = shouldPersist
    ? await conversations.resolveConversation(user.id, opts.conversationId, question)
    : null;

  if (conversation) {
    await conversations.appendMessage(conversation.id, {
      role: 'user',
      content: question,
    });
  }

  const prior = conversation
    ? (await conversations.recentHistory(conversation.id)).slice(0, -1)
    : [];

  const snapshot = await buildFinanceSnapshot(user.id);
  const system =
    'You are Santim, a warm personal-finance assistant. Answer ONLY from the provided JSON data about the user\'s ' +
    'own money. Be concise, specific and friendly, citing real numbers with the currency. ' +
    'The data includes a moneyTab section for loans, debts, and one-off expected payments between the user and other people - use it for questions about who owes whom, pending repayments, or expected incoming/outgoing money. ' +
    'If the data cannot answer the question, say so. ' +
    'Write the `answer` field in clean GitHub-flavoured Markdown: short paragraphs, **bold** for key figures, ' +
    'bullets for lists, and ## headings only when the reply has clear sections. Do not wrap the whole answer in a code fence. ' +
    'Return a JSON object: {"answer": string, "chart"?: {"type":"bar"|"donut","title":string,"data":[{"label":string,"value":number}]}}. ' +
    'Include a chart only when it genuinely helps visualise the answer (comparisons or breakdowns).';

  const prompt =
    prior.length > 0
      ? `DATA:\n${JSON.stringify(snapshot)}\n\nFollow-up question (use prior turns for context):\n${question}`
      : `DATA:\n${JSON.stringify(snapshot)}\n\nQUESTION: ${question}`;

  try {
    const { text, provider } = await runChat(user.id, {
      system,
      prompt,
      history: prior,
      json: true,
      maxTokens: 1800,
    });
    const parsed = parseJson<Omit<AskResult, 'provider' | 'conversationId' | 'messageId'>>(text);
    const answer = parsed?.answer || text || 'No answer produced.';
    const chart = parsed?.chart;

    let messageId: string | undefined;
    if (conversation) {
      const saved = await conversations.appendMessage(conversation.id, {
        role: 'assistant',
        content: answer,
        chart: chart ?? undefined,
        provider,
      });
      messageId = saved.id;
    }

    return {
      answer,
      chart,
      provider,
      conversationId: conversation?.id ?? '',
      messageId,
    };
  } catch (err) {
    if (conversation) {
      const message = err instanceof Error ? err.message : 'Something went wrong.';
      await conversations.appendMessage(conversation.id, {
        role: 'error',
        content: message,
      });
    }
    throw err;
  }
}

export interface ReviewResult {
  markdown: string;
  provider: string;
}

/** Monthly financial review - a personalized Markdown report with suggestions. */
export async function monthlyReview(user: AuthUser, month: string): Promise<ReviewResult> {
  const snapshot = await buildFinanceSnapshot(user.id);
  const system =
    'You are a supportive personal-finance coach writing a monthly money review. Use ONLY the facts ' +
    'in the provided JSON; never invent numbers. Output clean GitHub-flavoured Markdown with clear ' +
    'headings and short paragraphs. Cover: income vs spending for the requested month, how spending ' +
    'shifted between categories vs the previous month, how the budget plans are holding up (call out overspending kindly but ' +
    'honestly), and end with exactly 3 specific, actionable suggestions based on the ' +
    "user's real patterns. Do not wrap the output in code fences.";
  const prompt = `Write the review for ${month}.\n\nFINANCE DATA:\n${JSON.stringify(snapshot)}`;

  const { text, provider } = await runChat(user.id, { system, prompt, maxTokens: 3000 });
  return { markdown: text, provider };
}

export interface CategorizeResult {
  categoryId: string | null;
  categoryName: string | null;
  kind: 'INCOME' | 'EXPENSE' | null;
  payee: string | null;
  confidence: number;
  provider: string;
}

/** Suggest a category (from the user's own list) for a transaction description. */
export async function categorize(
  user: AuthUser,
  description: string,
  amount?: number,
  payee?: string,
): Promise<CategorizeResult> {
  const categories = await listUserCategories(user.id);
  const system =
    'You classify a personal financial transaction into EXACTLY ONE of the user\'s own categories. ' +
    'Return a JSON object: {"categoryName": string, "kind": "INCOME"|"EXPENSE", "payee": string|null, ' +
    '"confidence": number between 0 and 1}. categoryName MUST be copied verbatim from the provided list. ' +
    'Extract a clean payee/merchant name from the description if one is present.';
  const prompt =
    `CATEGORIES:\n${JSON.stringify(categories.map((c) => ({ name: c.name, kind: c.kind })))}\n\n` +
    `TRANSACTION: ${JSON.stringify({ description, amount, payee })}`;

  const { text, provider } = await runChat(user.id, { system, prompt, json: true, maxTokens: 300 });
  const parsed = parseJson<{ categoryName?: string; kind?: string; payee?: string; confidence?: number }>(text);

  const match = parsed?.categoryName
    ? categories.find((c) => c.name.toLowerCase() === parsed.categoryName!.toLowerCase())
    : undefined;

  return {
    categoryId: match?.id ?? null,
    categoryName: match?.name ?? null,
    kind: match?.kind ?? null,
    payee: parsed?.payee ?? null,
    confidence: Math.max(0, Math.min(1, parsed?.confidence ?? 0)),
    provider,
  };
}
