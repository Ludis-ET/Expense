import type { AuthUser } from '../../core/context.js';
import { buildProjectSnapshot, buildWorkspaceSnapshot } from './ai.context.js';
import { parseJson, runChat } from './ai.service.js';

export interface AskResult {
  answer: string;
  chart?: { type: 'bar' | 'donut'; title: string; data: { label: string; value: number }[] };
  provider: string;
}

/** "Ask your portfolio" — grounded NL Q&A with an optional chart spec. */
export async function ask(user: AuthUser, question: string): Promise<AskResult> {
  const snapshot = await buildWorkspaceSnapshot(user.orgId);
  const system =
    'You are an analyst for a research-management workspace. Answer ONLY from the provided JSON data. ' +
    'Be concise and specific, citing real numbers. If the data cannot answer the question, say so. ' +
    'Return a JSON object: {"answer": string, "chart"?: {"type":"bar"|"donut","title":string,"data":[{"label":string,"value":number}]}}. ' +
    'Include a chart only when it genuinely helps visualise the answer (e.g. comparisons or breakdowns).';
  const prompt = `DATA:\n${JSON.stringify(snapshot)}\n\nQUESTION: ${question}`;

  const { text, provider } = await runChat(user.id, { system, prompt, json: true, maxTokens: 1500 });
  const parsed = parseJson<Omit<AskResult, 'provider'>>(text);
  if (!parsed?.answer) return { answer: text || 'No answer produced.', provider };
  return { ...parsed, provider };
}

const REPORT_GUIDES: Record<string, string> = {
  progress: 'a concise progress report covering status, milestones achieved and upcoming, budget utilisation, and risks',
  funder: 'a formal report for a funder covering objectives, achievements, financial summary (planned vs spent), and next steps',
  proposal: 'a short proposal/concept note covering background, objectives, methodology, team, and an indicative budget',
};

export interface ReportResult {
  markdown: string;
  provider: string;
}

/** AI report & proposal co-writer — generates Markdown from real project data. */
export async function writeReport(user: AuthUser, projectId: string, type: string): Promise<ReportResult> {
  const snapshot = await buildProjectSnapshot(user.orgId, projectId);
  const guide = REPORT_GUIDES[type] ?? REPORT_GUIDES.progress;
  const system =
    'You are a research administrator writing polished documents. Use ONLY the facts in the provided JSON; ' +
    'do not invent results, citations, or numbers. Output clean GitHub-flavoured Markdown with clear headings, ' +
    'short paragraphs, and tables where useful. Do not wrap the output in code fences.';
  const prompt = `Write ${guide} for this project.\n\nPROJECT DATA:\n${JSON.stringify(snapshot)}`;

  const { text, provider } = await runChat(user.id, { system, prompt, maxTokens: 3000 });
  return { markdown: text, provider };
}

export interface ExtractResult {
  fields: Record<string, unknown>;
  provider: string;
}

/** Document intelligence — extract structured fields from pasted text. */
export async function extract(user: AuthUser, text: string): Promise<ExtractResult> {
  const system =
    'You extract structured bibliographic metadata from messy text (a reference, abstract, email, or citation). ' +
    'Return a JSON object with keys: title, authors (string), journal, doi, year (number|null), keywords (string[]), abstract. ' +
    'Use null or empty values for anything not present. Do not invent data.';
  const { text: out, provider } = await runChat(user.id, {
    system,
    prompt: text,
    json: true,
    maxTokens: 1200,
  });
  const fields = parseJson<Record<string, unknown>>(out) ?? {};
  return { fields, provider };
}
