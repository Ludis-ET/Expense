import type { AiProviderAdapter } from './types.js';

// OpenAI Chat Completions via REST (no SDK dependency needed for a single endpoint).
export const openaiAdapter: AiProviderAdapter = {
  id: 'openai',
  label: 'OpenAI (GPT)',
  defaultModel: 'gpt-4o',
  keysUrl: 'https://platform.openai.com/api-keys',
  async chat(cfg, req) {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${cfg.apiKey}`,
      },
      body: JSON.stringify({
        model: cfg.model || 'gpt-4o',
        max_tokens: req.maxTokens ?? 4096,
        messages: [
          { role: 'system', content: req.system },
          { role: 'user', content: req.prompt },
        ],
        ...(req.json ? { response_format: { type: 'json_object' } } : {}),
      }),
    });

    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(`OpenAI ${res.status}: ${detail.slice(0, 200)}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
    return data.choices?.[0]?.message?.content?.trim() ?? '';
  },
};
