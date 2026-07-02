import type { AiProviderAdapter, ProviderId } from './types.js';
import { anthropicAdapter } from './anthropic.js';
import { openaiAdapter } from './openai.js';
import { googleAdapter } from './google.js';

export const ADAPTERS: Record<ProviderId, AiProviderAdapter> = {
  anthropic: anthropicAdapter,
  openai: openaiAdapter,
  google: googleAdapter,
};

export const PROVIDER_IDS: ProviderId[] = ['anthropic', 'openai', 'google'];

/** Public catalog (no secrets) used to render the settings UI. */
export const PROVIDER_CATALOG = PROVIDER_IDS.map((id) => ({
  id,
  label: ADAPTERS[id].label,
  defaultModel: ADAPTERS[id].defaultModel,
  keysUrl: ADAPTERS[id].keysUrl,
}));

export type { AiProviderAdapter, ProviderId } from './types.js';
