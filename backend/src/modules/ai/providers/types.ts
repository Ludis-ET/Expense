export type ProviderId = 'anthropic' | 'openai' | 'google';

export interface ChatTurn {
  role: 'user' | 'assistant';
  content: string;
}

export interface ChatRequest {
  system: string;
  prompt: string;
  maxTokens?: number;
  /** Hint that the response must be a single JSON object. */
  json?: boolean;
  /** Prior turns in this conversation (oldest first). The current user turn is `prompt`. */
  history?: ChatTurn[];
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
