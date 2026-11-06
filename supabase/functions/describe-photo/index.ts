// Edge Function `describe-photo` (docs/features/ia-gemini.md).
import { claimQuota, geminiConfigured, generate } from '../_shared/gemini.ts';
import { handle } from './handler.ts';

Deno.serve((req) =>
  handle(req, {
    configured: geminiConfigured,
    claimQuota,
    generate: (prompt, schema, image) =>
      generate([{ inlineData: image }, { text: prompt }], schema),
  })
);
