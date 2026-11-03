# ADR-003 — Backend e autenticação

Estado: **Decidido em 2026-11-03** — Supabase Free (P-01), Google OAuth (P-02) e registo restrito ao proprietário (P-16). Recursos ainda não criados.

## Contexto

A necessidade de sync Android/PWA desde a primeira versão substitui a primeira ideia de backend apenas numa fase futura. Exportar manualmente não satisfaz este requisito.

## Backend

| Opção | Vantagens | Riscos/custos | Decisão |
|---|---|---|---|
| Supabase Free | SQL relacional, Auth, RLS e Storage no mesmo serviço | Quotas, pausa, sem backup automático Free; sync local não vem pronta | Candidato principal |
| Firebase/Firestore | SDKs e offline gerido em clientes suportados | Modelo documental; Storage exige Blaze/faturação | Alternativa, menos alinhada ao risco de custo inicial |
| Appwrite Cloud | Serviços integrados e alternativa legítima | Quotas e estratégia offline a confirmar; sem benefício decisivo já demonstrado | Não selecionado |
| PocketBase/Supabase/Appwrite self-hosted | Controlo e portabilidade possíveis | Hosting, segurança, backups e uptime a cargo do utilizador | Não recomendado para simplificar uso pessoal |
| Sem backend | Sem conta cloud | Falha a sincronização automática entre dispositivos | Excluído pelo requisito |

Supabase Storage privado e RLS são requisitos, não extras a adicionar depois de começar a guardar dados pessoais.

## Métodos de autenticação

| Método | Benefícios | Preparação/limites |
|---|---|---|
| Google OAuth | Sem password da app e sem email transacional próprio no fluxo principal | Projeto Google, consentimento e callbacks; dependência da conta Google |
| Email/password | Familiar e sem fornecedor social obrigatório | Confirmação/recuperação precisam de entrega de email fiável |
| Magic link/OTP email | Sem password memorizada | Depende de SMTP e limites de envio; rede necessária |
| Anónimo/local | Entrada rápida | Identidade/recuperação/sync entre dispositivos mais difíceis; não preferido |

Google é recomendação de avaliação, não uma decisão já tomada. Não abrir múltiplos métodos antes de demonstrar um fluxo de entrada e recuperação.

## Configuração atual a respeitar

Supabase utiliza chaves publicáveis no cliente e secretas no servidor. A chave publicável não identifica o utilizador nem substitui RLS.

O SMTP padrão tem alcance restrito e baixo limite de envios. Não planear o onboarding público em cima dessa entrega.

Se a app for só pessoal, definir quem pode criar/usar conta no servidor. Não contar apenas com esconder botões.

## Reversibilidade

Domínio separado reduz acoplamento, mas migrar Auth e Storage nunca é uma troca trivial de URL. Exportação e IDs de domínio ajudam; não prometem portabilidade sem migração.

## Aprovação e fontes

Antes de criar recursos: P-01, P-02 e P-16.

Guias: [Supabase](../guias/02-supabase-projeto-e-storage.md) e [login](../guias/03-login-e-configuracao.md). Preços, Firebase, SMTP e chaves: [Fontes](../fontes.md).
