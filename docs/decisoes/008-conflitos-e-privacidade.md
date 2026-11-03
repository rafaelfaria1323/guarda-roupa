# ADR-008 — Conflitos, sessões e privacidade (P-04)

Estado: **Proposto** (2026-11-03). Aguarda aprovação do utilizador; só depois P-04 passa a "Decidido".

Pressupostos já decididos: Supabase Free, Google OAuth, apenas o proprietário (P-01, P-02, P-16) e PowerSync como primeira POC (P-03).

## Contexto

Com dois dispositivos (Android e PWA no iPhone) que escrevem offline, o mesmo dado pode ser alterado nos dois antes de sincronizar. O PowerSync transporta as operações, mas o write path (upload para o Supabase) é nosso. A semântica do produto é decidida aqui, não pelo SDK.

## Princípios

1. **Nada se perde em silêncio.** Se uma alteração não for aplicada, fica visível como conflito ou como "rejeitada", com o motivo.
2. **Na dúvida, prevalece o estado mais conservador.** É melhor pedir confirmação do que dar como limpa uma peça suja ou ressuscitar uma peça apagada.
3. **O servidor arbitra a versão.** Cada linha mutável tem `version` (inteiro), incrementada no servidor. O relógio do telemóvel nunca decide.
4. **Operações com intenção, não "substituir a linha".** O cliente envia operações de domínio (`set_availability`, `confirm_plan_entry`, …) com `op_id` (UUID) e `base_version`. O servidor aplica-as numa transação através de funções SQL (RPC) validadas por RLS.
5. **Idempotência por `op_id`.** Repetir uma operação já aplicada devolve o mesmo resultado sem duplicar efeitos.

## Política por tipo de dado

| Caso | Regra proposta | O que o utilizador vê |
|---|---|---|
| Campos descritivos da peça (nome, notas, marca, atributos) | **Merge por campo.** Campos diferentes aplicam-se os dois. No mesmo campo com `base_version` desatualizada, ganha o que chegou primeiro ao servidor, e o valor perdido fica guardado no conflito. | Aviso "alterado noutro dispositivo" com opção de repor o valor local |
| Etiquetas/ocasiões da peça (conjuntos) | Merge de adições e remoções (união de adições; uma remoção só se aplica se a etiqueta existia na versão base) | Nada, salvo se houver um conflito real |
| Disponibilidade (`available` / `needs_cleaning` / `washing` / `drying`) | **Ordem conservadora.** Se as versões divergirem, prevalece o estado menos disponível: `needs_cleaning` > `washing` > `drying` > `available`. Voltar a `available` sobre uma base desatualizada **não** se aplica automaticamente. | Conflito "confirmar se está limpa", que se resolve com um toque |
| Arquivar/desarquivar | Arquivar prevalece sobre edições concorrentes, e a edição é aplicada na peça arquivada. Desarquivar sobre base desatualizada gera conflito. | Aviso discreto |
| Eliminação definitiva | **Tombstone** no servidor (`deleted_at`). Uma operação posterior com `base_version` anterior ao delete é rejeitada e **não ressuscita** a peça. | "Esta peça foi eliminada noutro dispositivo" e a alteração local fica guardada como rejeitada |
| Confirmar utilização de uma entrada de plano | **Única lógica por `plan_entry_id`.** Constraint `unique(plan_entry_id) where not voided`. A segunda confirmação devolve o `WearEvent` existente. | Mostra a utilização já registada |
| Utilizações manuais independentes (sem plano) | **Preservadas sempre**, mesmo que sejam próximas no tempo. Não se deduplicam por heurística. | Possibilidade de anular uma delas (operação rastreável `void_wear_event`) |
| Correção/anulação de utilização | Operação própria que marca `voided_at` e recalcula projeções na mesma transação. Nunca se apaga. | Histórico mostra "anulada" |
| Plano semanal editado nos dois dispositivos | Versão por `PlanEntry`. Com base desatualizada, a alteração passa a **proposta pendente** em vez de ser aplicada (coerente com "alterações ao plano só com confirmação"). | Proposta para aceitar ou rejeitar |
| Conjuntos guardados (`Outfit`) | Como os campos descritivos: merge por campo, com conflito nos itens se ambos alterarem a composição | Aviso com as duas composições |
| Fotografias (`MediaAsset`) | Imutáveis, identificadas por UUID e hash. Nunca há conflito de conteúdo. A associação a uma peça segue a regra das etiquetas. | Estado de upload por foto |

## Rejeições e conflitos

- O servidor responde a cada operação com `applied`, `merged`, `conflict` ou `rejected` (com motivo: `deleted`, `unauthorized`, `invalid`).
- Os conflitos ficam numa tabela local `sync_conflicts` (operação, valores local e remoto, motivo, data) até serem resolvidos. A UI mostra o número de conflitos pendentes no estado de sincronização.
- Erros de autorização ou validação **não** são repetidos indefinidamente: vão diretamente para `rejected`.
- Erros de rede e de sessão expirada mantêm a operação pendente, com retry e backoff.

## Sessões e logout

| Situação | Regra proposta |
|---|---|
| Sessão expirada | As escritas locais continuam e ficam pendentes. Pede-se novo login e a fila é retomada sem perda. |
| Logout sem pendências | Apaga a base local e a media local dessa conta neste dispositivo, após confirmação. |
| Logout com pendências | Bloqueia com aviso: "Há N alterações e M fotografias por enviar". As opções são *Sincronizar primeiro* (recomendado), *Exportar backup e sair* ou *Sair e descartar* (com confirmação explícita). |
| Entrar com outra conta | Cada conta tem a sua base local (nome do ficheiro/IndexedDB derivado do `user_id`). Nunca se reutiliza a base de outra conta, e as pendências da conta A nunca são enviadas na sessão B. |
| Conta não autorizada (P-16) | Login rejeitado no servidor através de uma allowlist de `user_id`/email, aplicada por hook de Auth e por RLS. A app mostra "conta sem acesso" e não cria base local. |

## Privacidade e autorização

- **RLS em todas as tabelas**, com `owner_id = auth.uid()`, também verificado nas FKs: uma operação não pode referenciar uma peça de outro utilizador.
- **Storage privado**, com caminhos `{user_id}/{asset_id}` e políticas que limitam leitura e escrita ao próprio prefixo. Não se guardam signed URLs, que são geradas quando são precisas.
- Regras de sincronização do PowerSync filtradas por `auth.uid()` (bucket por utilizador).
- No cliente só existem a URL do projeto e a *publishable key*. Nada de `service_role`, segredos OAuth ou tokens nos logs.
- Logs sem fotografias, nomes de peças ou tokens. Sem analytics de terceiros.

## Impacto no modelo de dados

Acrescenta a `modelo-de-dados.md`, quando aprovado:

- `version`, `updated_at` (servidor) e `deleted_at` nas entidades mutáveis sincronizadas;
- `voided_at` e `void_reason` em `WearEvent`;
- tabela servidor `applied_operations(op_id, owner_id, result, applied_at)` para idempotência;
- tabela local `sync_conflicts`;
- tabela servidor `allowed_users` para P-16.

## Como validar

Cenários da POC mínima em [Pendências](../pendencias.md) (passos 4 a 8) e E2E-04, E2E-11 e E2E-14 do [plano E2E](../plano-e2e.md), em especial:

1. Marcar a mesma peça como `needs_cleaning` no Android e `available` no iPhone, offline. Ao reconectar, fica `needs_cleaning` e o iPhone mostra o conflito.
2. Confirmar a mesma entrada de plano nos dois dispositivos. Fica com um único `WearEvent`.
3. Apagar no Android e editar offline no iPhone. A peça não ressuscita e a edição aparece como rejeitada.
4. Fazer logout com fotos por enviar. O logout é bloqueado, com as três opções.
5. Entrar com uma segunda conta Google não autorizada. O acesso é negado no servidor.

## Decisões pedidas ao utilizador

1. Aprovar a ordem conservadora de disponibilidade (`needs_cleaning` > `washing` > `drying` > `available`).
2. Aprovar que edições de plano com base desatualizada se tornem propostas.
3. Aprovar o comportamento de logout com pendências (três opções, com "Sincronizar primeiro" por defeito).
