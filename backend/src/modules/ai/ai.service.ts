import { Prisma } from '@prisma/client';
import { prisma } from '../../core/db.js';
import { BadRequestError } from '../../core/errors.js';
import { logger } from '../../core/logger.js';
import { decryptSecret, encryptSecret } from '../../core/crypto.js';
import { ADAPTERS, PROVIDER_CATALOG, PROVIDER_IDS, type ProviderId } from './providers/index.js';
import type { ChatRequest } from './providers/types.js';

interface StoredProvider {
  id: ProviderId;
  model: string;
  enabled: boolean;
  keyEnc: string | null;
}

export interface ProviderUpdate {
  id: ProviderId;
  model?: string;
  enabled: boolean;
  /** undefined = keep existing key, '' = clear key, otherwise set new key. */
  apiKey?: string;
}

async function readStored(userId: string): Promise<StoredProvider[]> {
  const row = await prisma.aiSetting.findUnique({ where: { userId } });
  const raw = (row?.providers as unknown as StoredProvider[]) ?? [];
  return Array.isArray(raw) ? raw : [];
}

/** Masked settings for the UI — every catalog provider is represented, in priority order. */
export async function getSettings(userId: string) {
  const stored = await readStored(userId);
  const byId = new Map(stored.map((p) => [p.id, p]));
  const ordered: StoredProvider[] = [
    ...stored.filter((p) => PROVIDER_IDS.includes(p.id)),
    ...PROVIDER_CATALOG.filter((c) => !byId.has(c.id)).map((c) => ({
      id: c.id,
      model: c.defaultModel,
      enabled: false,
      keyEnc: null,
    })),
  ];

  return {
    catalog: PROVIDER_CATALOG,
    providers: ordered.map((p) => ({
      id: p.id,
      label: ADAPTERS[p.id].label,
      model: p.model || ADAPTERS[p.id].defaultModel,
      enabled: p.enabled,
      hasKey: Boolean(p.keyEnc),
    })),
  };
}

export async function updateSettings(userId: string, updates: ProviderUpdate[]) {
  const existing = new Map((await readStored(userId)).map((p) => [p.id, p]));

  // Order of `updates` defines priority order.
  const next: StoredProvider[] = updates
    .filter((u) => PROVIDER_IDS.includes(u.id))
    .map((u) => {
      const prev = existing.get(u.id);
      let keyEnc = prev?.keyEnc ?? null;
      if (u.apiKey !== undefined) keyEnc = u.apiKey ? encryptSecret(u.apiKey) : null;
      return {
        id: u.id,
        model: (u.model || prev?.model || ADAPTERS[u.id].defaultModel).trim(),
        enabled: u.enabled,
        keyEnc,
      };
    });

  const providers = next as unknown as Prisma.InputJsonValue;
  await prisma.aiSetting.upsert({
    where: { userId },
    create: { userId, providers },
    update: { providers },
  });

  return getSettings(userId);
}

/** Enabled providers that have a usable key, in priority order, with decrypted keys. */
async function resolveChain(userId: string) {
  const stored = await readStored(userId);
  return stored
    .filter((p) => p.enabled && p.keyEnc)
    .map((p) => ({ id: p.id, model: p.model, apiKey: decryptSecret(p.keyEnc as string) }))
    .filter((p): p is { id: ProviderId; model: string; apiKey: string } => Boolean(p.apiKey));
}

export async function hasProvider(userId: string): Promise<boolean> {
  return (await resolveChain(userId)).length > 0;
}

/**
 * Run a chat completion through the user's providers in priority order.
 * If the highest-priority provider errors, fall through to the next one.
 */
export async function runChat(userId: string, req: ChatRequest): Promise<{ text: string; provider: ProviderId }> {
  const chain = await resolveChain(userId);
  if (chain.length === 0) {
    throw new BadRequestError('No AI provider configured. Add an API key under Settings → AI providers.');
  }

  const errors: string[] = [];
  for (const p of chain) {
    try {
      const text = await ADAPTERS[p.id].chat({ apiKey: p.apiKey, model: p.model }, req);
      if (text) return { text, provider: p.id };
      errors.push(`${p.id}: empty response`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warn({ provider: p.id, err: msg }, 'AI provider failed, falling through');
      errors.push(`${p.id}: ${msg}`);
    }
  }
  throw new BadRequestError(`All configured AI providers failed. ${errors.join(' · ')}`);
}

/** Lightweight connectivity check for a single provider. */
export async function testProvider(userId: string, id: ProviderId): Promise<{ ok: boolean; error?: string }> {
  const provider = (await resolveChain(userId)).find((p) => p.id === id);
  if (!provider) return { ok: false, error: 'Provider is not enabled or has no key' };
  try {
    const text = await ADAPTERS[id].chat(
      { apiKey: provider.apiKey, model: provider.model },
      { system: 'You are a connectivity check.', prompt: 'Reply with the single word: ok', maxTokens: 16 },
    );
    return { ok: Boolean(text) };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : 'Request failed' };
  }
}

/** Best-effort JSON extraction from a model response (handles ```json fences). */
export function parseJson<T>(text: string): T | null {
  const cleaned = text.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start === -1 || end === -1) return null;
  try {
    return JSON.parse(cleaned.slice(start, end + 1)) as T;
  } catch {
    return null;
  }
}
