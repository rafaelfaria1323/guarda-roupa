# Roadmap incremental

Estado: plano de 2026-10-31; o que já foi feito está em [Estado da implementação](#estado-da-implementação).

Não há estimativas de calendário sem conhecer disponibilidade e resultados das POCs. Cada incremento tem uma demonstração de valor e um gate explícito.

| Incremento | Entrega | Dependência | Gate para avançar |
|---|---|---|---|
| 0 — Fecho técnico | Login, backend, motor sync, baseline de dispositivos e UX essencial | Aprovar decisões abertas relevantes | P-01 a P-04 com plano claro |
| 1 — Fundação nos dois dispositivos | Conta, SQLite, uma peça com foto, sync, reabertura offline | Incremento 0 | A mesma peça/imagem existe no Android e iPhone/PWA; sem perda ao retomar |
| 2 — Catálogo e recuperação | CRUD, filtros, atributos, arquivo e exportação/recuperação inicial | Fundação | Dados e fotografias persistem; backups verificáveis |
| 3 — Uso e lavandaria | Confirmação real, histórico, recomendações e disponibilidade | Catálogo | Planeamento não conta como uso; indisponíveis não são candidatos |
| 4 — Conjuntos e estilo assistido | Guardar/classificar conjuntos e referências | Catálogo e histórico | Inspirações não aparecem como posse; categorias não fixam layers |
| 5 — Motor diário | Contexto, cores, padrões/texturas, conforto e razões | Atributos, políticas, estilo | Conjuntos completos válidos, incluindo t-shirt como top único |
| 6 — Semana utilizável | Reservas, pesquisa conjunta, diversidade e alterações propostas | Motor diário e eventos | Sete datas tratadas coerentemente, ou limitações explicadas |
| 7 — Entrada assistida por lojas | POC por loja e importador limitado | Infraestrutura estável e regras de acesso | Dados/variante confirmáveis, erros e alternativa manual |
| 8 — IA local | POC de modelo e runtime | Dados de qualidade e licença | Precisão/desempenho úteis na PWA, sem tornar a app dependente do modelo |
| 9 — Produto comercial | Multiutilizador público, pagamentos e operação | Utilidade validada e revisão de custos | Regras das lojas, autorização e obrigações operacionais |

## Estado da implementação

Atualizado a 2026-11-03. "Feito" quer dizer implementado, com testes automáticos (Dart e SQL) e migrações aplicadas. Não quer dizer validado em aparelho: os gates de dispositivo e os percursos do [Plano E2E](plano-e2e.md) continuam pendentes ([pendências](pendencias.md)).

| Incremento | Estado | Onde está descrito |
|---|---|---|
| 0 — Fecho técnico | Feito: Supabase, Google OAuth, PowerSync, ADR-008, CI com migrações automáticas | [pendências](pendencias.md) P-01 a P-04 |
| 1 — Fundação | Feito na app; falta a POC em dois dispositivos (P-03, guia 08 §7) e validar fotos no iPhone (P-05) | [sincronização](features/autenticacao-e-sincronizacao.md), [fotografias](features/fotografias-e-ficheiros.md) |
| 2 — Catálogo e recuperação | Feito: filtros, cores, atributos, eliminar, backup ZIP e recuperação para conta vazia | [guarda-roupa](features/guarda-roupa.md), [backups](features/backups-e-recuperacao.md) |
| 3 — Uso e lavandaria | Feito: "Vesti hoje", histórico, corrigir/desfazer, lavandaria (P-07) e rotatividade (P-06); backup v2 | [utilização](features/utilizacao-e-rotatividade.md), [lavandaria](features/lavandaria.md) |
| 4 — Conjuntos e estilo | Feito: conjuntos (backup v3), inspirações com link, imagem e proporções, preferências (backup v4/v5) | [conjuntos](features/conjuntos-e-ocasioes.md), [inspirações](features/inspiracoes-e-estilo.md) |
| 5 — Motor diário | Feito na base: motor (modelos, restrições, rotatividade, preferências, conforto P-17), previsão Open-Meteo com cache e localização (P-18), "Sugestões para hoje" no Planeador. Ficam para depois: harmonia de cores, padrões/texturas no conjunto, ecrã para editar os limites de conforto | [motor](features/motor-de-combinacoes.md) |
| 6 — Semana utilizável | Em curso: dados do plano (`plan_entries`, propostas pendentes, P-19). Falta a pesquisa semanal, o ecrã da semana e as alterações propostas | [motor](features/motor-de-combinacoes.md) |
| 7 a 9 | Por começar | — |

Ações do utilizador ainda abertas: voltar a fazer deploy das Sync Streams no painel do PowerSync quando um stream novo é adicionado a `powersync/sync-streams.yaml` (os de lavandaria, conjuntos, inspirações e preferências); executar a POC em dois dispositivos.

## MVP versus incremento

Incremento 1 é uma fundação, não o produto prometido. O MVP de planeamento semanal culmina no incremento 6, incluindo sync e estilo assistido.

Importação automática universal, Pinterest automático e IA visual avançada não bloqueiam esse MVP. Links podem ser guardados antes de serem interpretados automaticamente.

## Procedimento em cada incremento

1. Rever a feature, ADRs e pendências relevantes.
2. Resolver o gate que possa invalidar a implementação.
3. Identificar ações humanas e seguir o guia correspondente.
4. Implementar apenas o incremento e manter os contratos necessários.
5. Demonstrar os cenários de comportamento com dados isolados e persistência real.
6. Registar evidência, limitações, versões e decisões novas.
7. Só depois avançar.

## Ações do utilizador por fase

| Fase | Ação humana |
|---|---|
| Antes de criar serviços | Aprovar fornecedor/login e confirmar aceitação dos limites Free |
| Fundação | Criar contas, autorizar OAuth e disponibilizar Android/iPhone |
| Catálogo | Utilizar um conjunto de dados de experiência, sem necessidade de contar todo o guarda-roupa |
| Políticas | Rever limites de repetição e recomendações editáveis |
| UX/motor | Avaliar se propostas fazem sentido e indicar preferências explícitas |
| Distribuição | Instalar APK/PWA e preservar chave de assinatura |
| Operação | Confirmar recuperação e acompanhar consumo/pausas |

Ações com login, 2FA, aceitação de termos, segredos ou eventual pagamento são do utilizador. Não assumir que foram feitas sem confirmação.

## Critério de conclusão

Não basta compilar ou apresentar coverage. Os percursos relevantes de [Plano E2E](plano-e2e.md) devem ter resultado documentado no ambiente correspondente. Limitações de hardware/automação ficam “pendente”, não “passou”.
