// Edge Function `stylist` (docs/features/ia-gemini.md).
import { claimQuota, geminiConfigured, generate } from '../_shared/gemini.ts';
import { handle } from './handler.ts';

// Um pouco de variedade: "Outra ideia" não deve dar sempre o mesmo.
Deno.serve((req) =>
  handle(req, {
    configured: geminiConfigured,
    claimQuota,
    generate: (prompt, schema) => generate([{ text: prompt }], schema, 0.8),
  })
);
