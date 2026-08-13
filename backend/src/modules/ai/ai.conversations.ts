import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import { Prisma } from '../../core/prisma.js';

const TITLE_MAX = 80;
const HISTORY_LIMIT = 16;

function titleFromQuestion(question: string): string {
  const clean = question.replace(/\s+/g, ' ').trim();
  if (clean.length <= TITLE_MAX) return clean;
  return `${clean.slice(0, TITLE_MAX - 1).trimEnd()}…`;
}

export async function listConversations(userId: string) {
  const rows = await prisma.aiConversation.findMany({
    where: { userId },
    orderBy: { updatedAt: 'desc' },
    take: 50,
    include: {
      messages: {
        orderBy: { createdAt: 'desc' },
        take: 1,
        select: { content: true, role: true, createdAt: true },
      },
      _count: { select: { messages: true } },
    },
  });

  return {
    items: rows.map((c) => ({
      id: c.id,
      title: c.title,
      updatedAt: c.updatedAt,
      createdAt: c.createdAt,
      messageCount: c._count.messages,
      preview: c.messages[0]?.content?.slice(0, 120) ?? null,
    })),
  };
}

export async function createConversation(userId: string, title?: string) {
  const row = await prisma.aiConversation.create({
    data: {
      userId,
      title: (title?.trim() || 'New chat').slice(0, TITLE_MAX),
    },
  });
  return { id: row.id, title: row.title, createdAt: row.createdAt, updatedAt: row.updatedAt };
}

export async function getConversation(userId: string, id: string) {
  const row = await prisma.aiConversation.findFirst({
    where: { id, userId },
    include: {
      messages: { orderBy: { createdAt: 'asc' } },
    },
  });
  if (!row) throw new NotFoundError('Conversation not found');
  return {
    id: row.id,
    title: row.title,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    messages: row.messages.map((m) => ({
      id: m.id,
      role: m.role,
      content: m.content,
      chart: m.chart,
      provider: m.provider,
      createdAt: m.createdAt,
    })),
  };
}

export async function renameConversation(userId: string, id: string, title: string) {
  const existing = await prisma.aiConversation.findFirst({ where: { id, userId } });
  if (!existing) throw new NotFoundError('Conversation not found');
  const row = await prisma.aiConversation.update({
    where: { id },
    data: { title: title.trim().slice(0, TITLE_MAX) || 'New chat' },
  });
  return { id: row.id, title: row.title, updatedAt: row.updatedAt };
}

export async function deleteConversation(userId: string, id: string) {
  const existing = await prisma.aiConversation.findFirst({ where: { id, userId } });
  if (!existing) throw new NotFoundError('Conversation not found');
  await prisma.aiConversation.delete({ where: { id } });
  return { ok: true };
}

/** Ensure the conversation belongs to the user; create one if id is missing. */
export async function resolveConversation(userId: string, conversationId: string | undefined, firstQuestion: string) {
  if (conversationId) {
    const existing = await prisma.aiConversation.findFirst({
      where: { id: conversationId, userId },
    });
    if (!existing) throw new NotFoundError('Conversation not found');
    return existing;
  }
  return prisma.aiConversation.create({
    data: {
      userId,
      title: titleFromQuestion(firstQuestion),
    },
  });
}

export async function appendMessage(
  conversationId: string,
  input: {
    role: 'user' | 'assistant' | 'error';
    content: string;
    chart?: unknown;
    provider?: string | null;
  },
) {
  const chartValue =
    input.chart === undefined
      ? undefined
      : (input.chart as Prisma.InputJsonValue);

  const [message] = await prisma.$transaction([
    prisma.aiMessage.create({
      data: {
        conversationId,
        role: input.role,
        content: input.content,
        ...(chartValue !== undefined ? { chart: chartValue } : {}),
        provider: input.provider ?? null,
      },
    }),
    prisma.aiConversation.update({
      where: { id: conversationId },
      data: { updatedAt: new Date() },
    }),
  ]);
  return message;
}

/** Last N user/assistant turns for multi-turn context (excludes errors). */
export async function recentHistory(conversationId: string) {
  const rows = await prisma.aiMessage.findMany({
    where: {
      conversationId,
      role: { in: ['user', 'assistant'] },
    },
    orderBy: { createdAt: 'desc' },
    take: HISTORY_LIMIT,
    select: { role: true, content: true },
  });
  return rows.reverse().map((m) => ({
    role: m.role as 'user' | 'assistant',
    content: m.content,
  }));
}
