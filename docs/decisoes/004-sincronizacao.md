# ADR-004 — Sincronização local-first

Estado: decisão de implementação em aberto; POC recomendada antes de construir o catálogo completo.

## Contexto e requisitos

Sync automática desde o início, ao abrir/usar/reconectar. Escritas offline persistentes, histórico correto, ficheiros privados e estado visível. Não há exigência de execução com a PWA fechada.

Supabase não sincroniza automaticamente uma base Drift.

## Alternativas

| Solução | Benefícios | Obrigações/limites | Avaliação |
|---|---|---|---|
| PowerSync + Supabase | Motor estabelecido, menor reinvenção de transporte offline | Serviço extra, quotas, integração Auth/Drift/Safari e write path a comprovar | Primeira POC recomendada |
| Outbox e protocolo próprios | Controlo e ausência de outro serviço cloud | Toda a correção de sync, migrações e manutenção fica na aplicação | Alternativa séria, não “umas chamadas HTTP” |
| Supabase Realtime apenas | Baixa latência de avisos online | Não é fila offline nem protocolo completo | Insuficiente isoladamente |
| Firestore | Offline integrado em clientes suportados | Troca de modelo/backend e condição Blaze para media | Alternativa arquitetural |
| Dump/restore automático | Implementação aparentemente simples | Colisões, perda de alterações e grandes transferências | Rejeitado como sync |

## Facto novo relevante: PowerSync Free

A página atual anuncia 2 GB/mês de dados sincronizados, 500 MB alojados e 50 clientes simultâneos, sem cartão. Não é correto descartá-lo por assumir que só existe um plano pago.

Há discrepância no prazo de desativação por inatividade. Confirmar antes da decisão. Ficheiros continuam a precisar de pipeline/storage; não confundir estes limites com capacidade de fotografias.

Integração concreta de SDK, Drift, Auth e Safari deve ser verificada com as versões escolhidas. Se PowerSync gerir SQLite, usar o adaptador suportado: não adicionar uma conexão Drift independente para os mesmos dados.

## Requisitos para uma opção própria

1. Mutação de domínio + outbox na mesma transação local.
2. Operação com identidade estável, versão base e validação autorizada.
3. Replay/retries idempotentes e transações do lado servidor.
4. Snapshot/bootstrap e feed incremental com ordenação comprovada.
5. Tombstones, retenção e rebootstrap de clientes antigos.
6. Política de conflitos por operação/domínio.
7. Assets imutáveis e tratamento explícito de falhas parciais.
8. Migrações, logout e recuperação de conta sem perder pendências.

Timestamps de clientes não são um cursor global fiável. Uma sequence SQL isolada pode atribuir números antes de outra transação fazer commit: não assumir que “buscar IDs maiores que o último” nunca perde alterações.

Preferir mecanismo estabelecido ou provar formalmente/por cenários concorrentes a ordenação e bootstrap escolhidos.

## Conflitos semânticos

“Last write wins” por relógio do telefone pode disponibilizar roupa suja ou apagar escolhas. Separar conflitos descritivos de disponibilidade, plano e histórico.

A mesma entrada planeada tem confirmação única lógica. Duas ações manuais independentes não podem ser identificadas como iguais só pela proximidade temporal.

Um delete não deve ser revertido por um dispositivo desatualizado. Se tombstones expirarem, forçar bootstrap em vez de aceitar replay cego.

SDKs de sync não eliminam estas decisões de negócio.

## POC e critério de escolha

Executar o percurso P-03 em [Pendências](../pendencias.md) num Android e PWA/iPhone reais. Incluir auth expirada, media e isolamento.

Escolher uma opção se demonstrar correção, simplicidade operacional e custo zero dentro dos limites pessoais. Se o fornecedor falhar um requisito essencial, comparar a alternativa própria com o custo real de engenharia.

Não ativar um plano pago como solução automática. Não construir ambas as opções completas.

## Fontes e impactos

Pricing PowerSync verificado; integração detalhada permanece gate. Fontes: [registo](../fontes.md).

Impacta [stack](../stack.md), [modelo](../modelo-de-dados.md), [auth/sync](../features/autenticacao-e-sincronizacao.md) e [backups](../features/backups-e-recuperacao.md).
