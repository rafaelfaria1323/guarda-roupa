// Edge Function `describe-photo` (docs/features/ia-gemini.md).
import { claimQuota, geminiConfigured, generate, labelModel } from '../_shared/gemini.ts';
import { handle } from './handler.ts';

Deno.serve((req) =>
  handle(req, {
    configured: geminiConfigured,
    claimQuota,
    generate: async (kind, prompt, schema, images) => {
      const parts = [...images.map((inlineData) => ({ inlineData })), {
        text: prompt,
      }];
      if (kind !== 'label') return generate(parts, schema);
      // Etiquetas: primeiro o modelo mais forte; sem quota ou indisponível,
      // o modelo de sempre.
      const strong = await generate(parts, schema, 0, {
        model: labelModel,
        timeoutMs: 45_000,
      });
      if ('status' in strong && [404, 429, 500, 503].includes(strong.status)) {
        return generate(parts, schema);
      }
      return strong;
    },
  })
);
