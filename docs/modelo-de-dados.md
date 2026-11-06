# Modelo de dados proposto

Estado: desenho lógico; não é uma migração SQL pronta para executar. Data: 2026-10-31.

## Convenções

- IDs estáveis UUID para entidades e operações; não depender de IDs locais autoincrementais para identidade entre dispositivos.
- Timestamps de eventos guardados em UTC, com contexto de fuso quando relevante.
- Datas planeadas guardadas como datas locais e fuso do plano, não como “meia-noite UTC” reinterpretada no telefone.
- Categorias e estados usam identificadores estáveis, com tradução na apresentação.
- Metadados desconhecidos são desconhecidos, não falsos nem valores neutros inventados.
- As colunas de versão/sync dependem da escolha do [ADR-004](decisoes/004-sincronizacao.md).

## Entidades principais

| Entidade | Campos/conteúdo principal |
|---|---|
| `Profile` | Utilizador autenticado, preferências, cidade e fuso |
| `Wardrobe` | ID, proprietário, nome; um inicialmente |
| `Garment` | Guarda-roupa, categoria, nome, atributos, disponibilidade, arquivo |
| `GarmentColor` | Peça, RGB de referência, proporção e origem/confirmado |
| `GarmentOccasion` | Peça e ocasião adequada |
| `MediaAsset` | Proprietário, ID/hash, MIME, dimensões, variante, estado local/cloud |
| `GarmentMedia` | Peça, asset e posição |

**Implementação atual das fotografias (incremento 1).** Enquanto só as peças têm imagens, `MediaAsset` + `GarmentMedia` ficam numa coluna JSON tipada `garments.photos` (até 5; a primeira é a capa): `{id, width, height, bytes, thumb_bytes, sha256}`, validada no servidor (`garment_photos_valid`). Os ficheiros JPEG (1600 px e miniatura 320 px, sem metadados) estão no bucket privado `garment-photos` em `{utilizador}/{foto}/main.jpg|thumb.jpg`, e neste dispositivo na tabela SQLite local `photo_files` (fora do schema sincronizado; apagada ao terminar sessão). Os embeddings FashionCLIP das fotos já comparadas ficam na tabela local `photo_embeddings` (`photo_id`, `model`, `data` float32), também fora do schema e apagada ao terminar sessão; recalculam-se se faltarem. As operações `attach_photo`/`detach_photo` passam por `apply_garment_operation`; `attach_photo` só aceita a foto se os dois ficheiros já existirem no Storage. Separar em tabelas quando outras entidades (conjuntos, inspirações) tiverem imagens.

**Implementação atual dos conjuntos (incremento 4).** `Outfit` é a tabela `outfits` (`name` opcional, `occasions` JSON validado por `garment_occasions_valid`, `deleted_at`); `OutfitItem` e `OutfitOccasion` ficam em colunas JSON: `items = [{garment_id, role}]`, validada por `outfit_items_valid` (1–20, peças únicas, um só `main_top`/`bottom`/`one_piece`/`footwear`). A ordem da lista é a ordem de camada. Uma peça eliminada não apaga o conjunto.

**Implementação atual do plano (incremento 6).** `PlanEntry` + `PlanEntryItem` são a tabela `plan_entries`, uma entrada ativa por utilizador e dia (`unique (owner_id, day) where deleted_at is null`). Não há tabela `WeekPlan`: a semana são os 7 dias a partir de uma data. Campos:
- `day` (data de calendário) e `occasion` (`null` = “a decidir”);
- `tentative`: o dia pode não acontecer (fim de semana, P-19);
- `items`: como `outfits.items`, mas pode estar vazio (`plan_items_valid`);
- `status`: `proposed` ou `accepted`. “Confirmada” e “não utilizada” não se guardam: vêm de `wear_events.plan_entry_id` e da data;
- `version`: sobe no servidor a cada alteração aplicada;
- `proposal`: alteração pendente (só os campos `occasion`, `tentative`, `items`, `status`) que chegou com `base_version` desatualizada, ou um segundo `create` para o mesmo dia (ADR-008);
- `deleted_at`.

O plano não entra no backup (como o `plan_entry_id` das utilizações). Escritas por `apply_plan_operation` (`create_plan_entry`, `edit_plan_entry` com `base_version`, `resolve_plan_proposal`, `delete_plan_entry`).

**Quota da importação por link (incremento 7).** Tabela `import_requests` (`owner_id`, `requested_at`), sem acesso dos clientes e sem dados de produto: serve só para `claim_import_quota()` limitar a função `import-product` a 30 pedidos por hora e 200 por dia. Pedidos com mais de um dia são apagados. Não sincroniza nem entra no backup.

**Perfis de sites e imagens autorizadas (importação de qualquer site).** `import_domains` (`host`, `ok_count`, `fail_count`, `consecutive_failures`, `last_result`, `last_source`, `first_seen`, `last_seen`) é global e criada sozinha por `record_import()` a cada importação (o resultado `shared`, de uma página partilhada pelo atalho do iPhone, só autoriza imagens e não conta); o estado (`new`, `testing`, `works`, `failing`) sai de `import_domain_status()`. Não tem links, produtos nem utilizadores. `import_image_grants` (`owner_id`, `url_hash` = md5 do URL, `expires_at` a 1 dia) diz que imagens a função pode copiar para cada utilizador (`import_image_allowed()`). Sem acesso direto dos clientes, não sincroniza nem entra no backup.

**Caixa do atalho do iPhone.** `import_inbox_keys` (`owner_id` chave primária, `key_hash` = SHA-256 hex da chave, `created_at`, `last_used_at`): no máximo uma chave por utilizador, criada por `create_import_inbox_key()` (devolve a chave uma vez), apagada por `revoke_import_inbox_key()`, consultada por `import_inbox_key_status()`. `import_inbox` (`id`, `owner_id`, `url` ≤ 2048, `preview` jsonb ≤ 64 kB, `created_at`, `expires_at` a 7 dias): as pré-visualizações que o atalho mandou, escritas só por `submit_import_inbox()` (anónimo, com a chave), lidas por `list_import_inbox()` e apagadas por `discard_import_inbox()` ou ao expirar. Máximo 20 por utilizador. O `preview` é o de uma peça (com `product`) ou, desde 2026-11-06, o de uma inspiração (`kind: "inspiration"`, `site`, `url`, `inspiration: {title, description}`), de um Pin ou publicação do Instagram. Sem acesso direto dos clientes, não sincroniza nem entra no backup: são pedidos de passagem.

**Implementação atual das inspirações (incremento 4).**
- `Inspiration` é a tabela `inspirations`, com estes campos:
  - `title` e/ou `source_url`, pelo menos um dos dois, e o link só `http(s)`;
  - `notes`;
  - `palette`: JSON de RGB distintos, até 8;
  - `formality`: `relaxed`, `smart_casual` ou `dressy`;
  - `patterns`, `textures` e `occasions`: JSON de ids conhecidos;
  - `proportions`: JSON de ids conhecidos (`fitted_top_relaxed_bottom`, `relaxed_top_fitted_bottom`, `all_fitted`, `all_relaxed`, `long_layer`, `cropped_top`);
  - `image`: `null` ou um objeto com a forma de uma foto de peça (`id`, `width`, `height`, `bytes`, `thumb_bytes`, `sha256`), validado por `garment_photos_valid`; os ficheiros vivem no bucket `garment-photos`;
  - `deleted_at`.
- `StylePreference` é a tabela `style_preferences`, com estes campos:
  - `subject` (`color`, `pattern`, `texture`, `formality`, `combo`) e `value`, validado por `style_preference_value_valid` (cor: RGB em decimal; os outros: ids conhecidos; combinações `neutral_base`, `single_accent`, `tonal`, `high_contrast` e `low_contrast`, as duas últimas desde a migração `20261117000001`);
  - `stance`: `like` ou `avoid`;
  - `occasions`: o contexto (vazio = sempre);
  - `inspiration_id`: a origem opcional (só do próprio; fica `null` se a inspiração for apagada de vez);
  - `deleted_at`.

**Categorias de acessório (2026-11-06).** `garments.category` aceita também `scarf`, `beanie`, `gloves`, `hat`, `sunglasses`, `umbrella`, `belt` e `bag` (migração `20261120000001`); `accessory` passa a ser “outro acessório”. Sem coluna nova.

**Atributos da peça (incremento 2).** Colunas opcionais em `garments`, `null` = desconhecido: `pattern` (plain, stripes, checks, dots, floral, print, other), `texture` (smooth, ribbed, knit, textured, fuzzy), `warmth` (light, medium, warm), `rain_ok`/`wind_ok` (boolean), `formality` (relaxed, smart_casual, dressy; os mesmos ids das inspirações, 2026-11-06), `fit` (fitted, regular, relaxed) e `length` (cropped, regular, long), corte e comprimento desde a migração `20261118000001`, `wash` (machine_30, machine_40, machine_60, hand, professional) e `tumble_dry` (boolean), lavagem e máquina de secar desde a migração `20261119000001`, `occasions` (jsonb, lista sem repetidos de casual, work_casual, evening; vazia = desconhecido), `material` (≤ 120) e `care` (≤ 300) como texto livre da etiqueta. Os IDs são validados no servidor por `check`; o cliente ignora valores que não conhece (versões futuras). Cada atributo é um campo do `edit`, com `from`/`to` para conflitos campo a campo.
| `Occasion` | ID estável, nome e regras/preferências |
| `Outfit` | Conjunto guardado, nome, estado |
| `OutfitItem` | Conjunto, peça, papel contextual, ordem de camada |
| `OutfitOccasion` | Classificações do conjunto |
| `WeekPlan` | Intervalo de datas, fuso, versão aceite |
| `PlanEntry` | Data local, ocasião, estado, bloqueio manual, contexto utilizado |
| `PlanEntryItem` | Snapshot da composição planeada: peça e papel |
| `WearEvent` | Utilização confirmada, instante, data local e entrada de plano opcional |
| `WearEventItem` | Peças efetivamente usadas e respetivos papéis |
| `LaundryEvent` | Peça, transição real, instante e dados necessários de cuidado |
| `RotationPolicy` | Categoria/override, intervalo, modo e exceções autorizadas |
| `LaundryPolicy` | Categoria/override, limiar recomendado e automatismo opcional |
| `Inspiration` | Referência visual, link de origem, etiquetas confirmadas e ocasiões |
| `StylePreference` | Preferência explícita, origem e contexto; não posse |
| `WeatherCache` | Localização aproximada, previsão, fornecedor e atualização |

Não criar uma tabela genérica de atributos sem estrutura apenas para evitar pensar nas queries. Os detalhes opcionais podem usar formatos tipados, sem perder integridade dos campos centrais.

## Categoria versus papel

`Garment.category = t_shirt` não implica `base_layer`.

O papel é atribuído em `OutfitItem`, `PlanEntryItem` e `WearEventItem`. Uma peça pode suportar vários papéis, mas só aparecer uma vez na mesma composição.

Um conjunto simples com t-shirt, calças e ténis não precisa de uma camada adicional.

## Disponibilidade versus recomendação

Disponibilidade: `available`, `needs_cleaning`, `washing`, `drying` e, desde 2026-11-06, `at_cleaners` (na lavandaria / limpeza profissional). Arquivar é `archived_at`, não um estado.

O aviso `cleaning_recommended` é derivado da política/histórico e não é mais um estado de indisponibilidade. Um aviso não altera por si só `available`.

Se existir conflito de disponibilidade entre dispositivos, a política de segurança/UX deve ser decidida no gate de sync. A recomendação é não tratar um estado incerto como “limpo confirmado”.

## Histórico e snapshots

Editar um conjunto guardado não altera um plano aceite nem uma utilização passada. As composições planeada e realmente usada são registadas separadamente.

Arquivar uma peça preserva referências históricas. A eliminação definitiva e os seus efeitos em histórico/backups exigem confirmação e política explícita.

Corrigir uma utilização deve ser uma operação rastreável, não apagar silenciosamente contadores. Contadores, se materializados por desempenho, são projeções reconstruíveis e atualizadas na mesma transação.

## Lembretes (2026-11-06)

Tabelas só do servidor (fora do PowerSync), com RLS e sem acesso direto, a não ser ler as próprias definições. Escreve-se por RPC ([lembretes](features/lembretes.md)):

| Tabela | Campos | Escrita |
|---|---|---|
| `reminder_settings` | `owner_id` (pk), `wear_check_at`, `eve_at` (`time`, `null` = desligado), `time_zone` (IANA, validado) | `set_reminder_settings` |
| `push_subscriptions` | `endpoint` (pk, https), `owner_id`, `p256dh`, `auth` | `save_push_subscription` (o mesmo aparelho passa para a conta que o guardou), `remove_push_subscription`; o envio apaga os desaparecidos com `drop_push_subscriptions` |
| `day_summaries` | `(owner_id, day)` pk, `plan_version`, `wear_body`, `eve_body` (≤ 300) | `set_day_summaries` (até 14 dias; apaga os passados). Só se usa se `plan_version` for a versão atual da entrada do plano |
| `reminder_sends` | `(owner_id, day, kind)` pk, `kind` ∈ `wear_check`, `eve` | `claim_due_reminders`, só com o token do cron (`private.reminder_cron`) |

## Leitura de fotos com o Gemini (2026-11-06)

Tabela só do servidor, sem acesso direto ([Gemini](features/ia-gemini.md)):

| Tabela | Campos | Escrita |
|---|---|---|
| `photo_ai_requests` | `id`, `owner_id`, `requested_at` | `claim_photo_ai_quota` (até 60 por hora e 300 por dia; apaga o que tem mais de um dia) |

A opção "Usar o Gemini neste aparelho" fica só no aparelho, em `local_settings` (`gemini_photos`). As [peças que faziam falta](features/pecas-em-falta.md) guardam aí também o orçamento por peça (`shopping_budget`) e as ideias postas de lado (`shopping_dismissed`, lista JSON).

O aspeto da app (Automático, Claro ou Escuro) fica fora da base, no `localStorage` do browser (`fio.theme_mode`), para se aplicar logo ao abrir, mesmo antes de entrar na conta.

## Sync: campos condicionais

Na opção própria: outbox durável com ID de operação, entidade, versão base, payload e estado; receção com cursor de servidor comprovado e tombstones.

Na opção SDK: usar os mecanismos do fornecedor e as tabelas locais suportadas; não construir outra fila duplicada sem necessidade.

Uma confirmação da mesma entrada de plano deve ser idempotente no servidor. IDs diferentes de registos manuais independentes não provam que se trata da mesma utilização física.

## Campos de sincronização e conflitos (ADR-008)

Decidido em [ADR-008](decisoes/008-conflitos-e-privacidade.md):

- Entidades mutáveis sincronizadas: `version` (inteiro, incrementado pelo servidor), `updated_at` (servidor) e `deleted_at` (tombstone).
- `WearEvent`: `voided_at` e `void_reason`; anular nunca apaga.
- Servidor: `applied_operations(op_id, owner_id, result, applied_at)` para idempotência.
- Servidor: `allowed_users` para restringir o acesso ao proprietário (P-16).
- Local: `sync_conflicts` com operação, valores local e remoto, motivo e data, até ser resolvido.

## Constraints e índices candidatos

| Regra/query | Implementação proposta |
|---|---|
| Peça única numa composição | Unique por composição e `garment_id` |
| Um conjunto diário no MVP | Restrição por plano/data; migração explícita para vários slots depois |
| Uma confirmação ativa da mesma entrada | Constraint/operador idempotente no servidor, com caminho definido para correções |
| Histórico por peça/data | Índice nas referências a peça e instante/data |
| Lista de inventário | Índices por guarda-roupa, arquivo, categoria e disponibilidade segundo as queries |
| Propriedade | FKs e autorização para impedir referências cruzadas entre utilizadores |
| Operação repetida | Identificador de operação único dentro do âmbito autorizado |

Não criar índices para todas as colunas. Confirmar com queries e perfis reais.

## Imagens, eliminação e recuperação

Assets imutáveis podem ser deduplicados por conteúdo, sem fundir peças físicas. Apagar uma referência não apaga imediatamente um asset ainda usado por outra entidade.

O backup contém IDs e ficheiros, não URLs temporárias nem tokens. A recuperação tem de preservar identidade e não reenviar eventos históricos como novas utilizações. Para juntar a uma conta com dados (P-11), a app lê no Supabase, pela RLS (`*_select_own`), os ids do backup com `deleted_at`/`voided_at` preenchido em `garments`, `wear_events`, `cleaning_events`, `outfits`, `inspirations` e `style_preferences`: essas linhas não chegam ao dispositivo pelo stream.

Ver [Backups](features/backups-e-recuperacao.md) e [Plano E2E](plano-e2e.md).
