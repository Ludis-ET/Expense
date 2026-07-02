export type ProviderId = 'anthropic' | 'openai' | 'google';

export interface ChatRequest {
  system: string;
  prompt: string;
  maxTokens?: number;
  /** Hint that the response must be a single JSON object. */
  json?: boolean;
}

export interface ProviderRuntimeConfig {
  apiKey: string;
  model?: string;
}

export interface AiProviderAdapter {
  id: ProviderId;
  label: string;
  defaultModel: string;
  /** Where the user gets an API key (shown in the UI). */
  keysUrl: string;
  chat(cfg: ProviderRuntimeConfig, req: ChatRequest): Promise<string>;
}
