# Configuração pública

`public.json` é lido com `flutter run --dart-define-from-file=config/public.json`.

Só contém valores **públicos**, que acabam dentro da app (APK/PWA) de qualquer forma:

| Chave | Origem |
|---|---|
| `SUPABASE_URL` | Supabase > Connect > Project URL |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase > Connect (`sb_publishable_...`) |
| `POWERSYNC_URL` | PowerSync Dashboard > instância > Connect |

A proteção dos dados vem da RLS, da allowlist (P-16) e das Sync Streams filtradas por utilizador, não do segredo destas chaves.

**Nunca** pôr aqui: `sb_secret_...`, `service_role`, a password da base, o Client Secret do Google ou a password do role do PowerSync.
