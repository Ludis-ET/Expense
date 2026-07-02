import Anthropic from '@anthropic-ai/sdk';
import type { AiProviderAdapter } from './types.js';

// Claude via the official Anthropic SDK. The API key is supplied per request
// (decrypted from the user's stored settings), so we construct a client per call.
export const anthropicAdapter: AiProviderAdapter = {
  id: 'anthropic',
  label: 'Claude (Anthropic)',
  defaultModel: 'claude-opus-4-8',
  keysUrl: 'https://console.anthropic.com/settings/keys',
  async chat(cfg, req) {
    const client = new Anthropic({ apiKey: cfg.apiKey });
    const message = await client.messages.create({
      model: cfg.model || 'claude-opus-4-8',
      max_tokens: req.maxTokens ?? 4096,
      system: req.json ? `${req.system}\n\nRespond with a single valid JSON object and nothing else.` : req.system,
      messages: [{ role: 'user', content: req.prompt }],
    });
    return message.content
      .map((block) => (block.type === 'text' ? block.text : ''))
      .join('\n')
      .trim();
  },
};
