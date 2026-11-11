# Arquitetura

Estado: recomendada; fornecedores e mecanismo de sync sujeitos aos ADRs. Data: 2026-10-31.

## Princípios

Aplicação local-first, organizada por feature, com Repository Pattern obrigatório e domínio em Dart puro. Não começar com microserviços, um framework genérico de CRUD ou múltiplos pacotes internos sem necessidade.

## Responsabilidades

| Camada | Responsabilidade | Não deve fazer |
|---|---|---|
| Apresentação | Widgets, navegação e estado transitório da interação | SQL, HTTP, regras de lavagem/combinação |
| Aplicação | Coordenar ações, transações e resultados de casos de uso | Conhecer detalhes visuais ou fazer recomendações estéticas ad hoc |
| Domínio | Entidades, políticas, gerador, planeador e contratos necessários | Depender de Flutter, Supabase, Drift ou browser |
| Dados | Repositórios concretos, mapeamento e integração de fontes | Exportar linhas Drift ou DTOs cloud como modelo de UI |
| Adaptadores | Persistência, imagens, rede, relógio e plataforma | Esconder indisponibilidade ou inventar resultados |

Riverpod compõe dependências e expõe estado. Os providers não substituem o domínio nem criam uma cópia paralela do catálogo.

## Organização proposta

No futuro repositório, usar `features/wardrobe`, `outfits`, `planner`, `laundry`, `inspirations` e `account_sync`. Cada feature tem apenas as subdivisões de que necessita. Elementos genuinamente partilhados ficam num núcleo pequeno.

Não criar um “shared” com toda a lógica nem uma interface para cada classe sem justificação.

## Repository Pattern

Contratos orientados ao negócio, como observar o guarda-roupa, confirmar uma utilização ou obter o estado de sincronização. Evitar um `BaseRepository<T>` com dezenas de métodos genéricos.

Transações que envolvem histórico, estado e outbox pertencem à implementação coordenada, não a uma sequência de chamadas independentes feita pelo widget.

Erros de domínio, indisponibilidade de serviço e conflitos são resultados distintos. Uma lista vazia não pode representar silenciosamente falha de rede.

## Fonte de verdade e sincronização

Para a interface, a visão de trabalho é a base local, observada através dos repositórios. O servidor arbitra versões e aceita alterações partilhadas entre dispositivos.

Isto não são duas fontes concorrentes para o mesmo widget: a sincronização atualiza a visão local e o estado de confirmação. A UI não mistura diretamente respostas Realtime com resultados Drift.

Estados mínimos: `local_pending`, `syncing`, `synced`, `failed`, `conflict`. “Guardado localmente” e “disponível no outro dispositivo” não são a mesma confirmação.

O protocolo ou SDK deve garantir repetição segura de operações, retomada, deletes e recuperação após perda de ligação. Ver [ADR-004](decisoes/004-sincronizacao.md).

## Operações relevantes

| Operação | Fronteira atómica necessária |
|---|---|
| Confirmar utilização | Evento + peças associadas + estado do plano + alteração pendente |
| Alterar disponibilidade | Evento/versão + disponibilidade + invalidação de sugestões afetadas |
| Aceitar novo plano | Nova composição/versão + reservas, sem criar utilizações |
| Adicionar fotografia | Preparação do ficheiro + referência consistente; upload remoto confirmado separadamente |
| Recuperar backup | Preparação e verificação completas antes de ativar o conjunto de dados |

Ficheiros e SQL não partilham uma transação física. Usar staging, referências imutáveis e limpeza de órfãos identificados, não fingir atomicidade entre serviços.

## Ficheiros privados

No Android, bytes numa pasta privada persistente. Na Web, IndexedDB ou adaptador comprovado. A base referencia `MediaAsset.id`.

Na cloud, buckets privados e caminhos autorizados por utilizador. Não guardar signed URLs como identidade permanente. Reconstruí-las ou descarregar bytes com sessão válida.

Não declarar uma fotografia totalmente sincronizada enquanto o upload estiver pendente.

## Identidade e isolamento

Todas as entidades sincronizadas têm proprietário ou associação inequívoca ao guarda-roupa. RLS e políticas de Storage restringem acesso no servidor. Esconder ecrãs não é autorização.

No logout/troca de conta, dados locais e operações pendentes não podem aparecer na conta seguinte. Não descartar alterações não sincronizadas sem aviso e decisão explícita.

A app distribuída usa apenas uma chave publicável; secrets do backend nunca entram no APK, PWA ou Markdown.

## Motor e contexto

Os repositórios fornecem um snapshot consistente de peças, políticas, histórico, reservas e contexto meteorológico identificado. O motor devolve candidatos, razões, avisos e qualidade da pesquisa.

Categoria e papel contextual são distintos: a mesma t-shirt pode ser `main_top` num conjunto e `base_layer` noutro. Não duplicar a peça no mesmo conjunto.

## Diagnóstico (2026-11-11)

A app não tem serviço de erros: nada sai do aparelho sozinho. Para se perceber o que falhou no telemóvel, há **Definições › Diagnóstico** (`lib/core/diagnostics/`):

- **O que mostra:** a versão publicada (`BUILD_ID`: o commit e a hora da build, postos por `tool/web/build_pwa.sh`), o browser, o estado da sincronização (ligada, pendentes, conflitos, última vez, erro) e os últimos 40 erros.
- **O que regista:** os erros que o Flutter apanha (`FlutterError.onError`, "ecrã") e os que ficam por tratar (`PlatformDispatcher.onError`, "fundo"), ligados em `main.dart`. Código novo pode chamar `DiagnosticsLog.instance.record(onde, erro)`.
- **Cuidados:** cada erro fica com a mensagem e as 3 primeiras linhas da pilha, até 400 caracteres; o que tem cara de chave é retirado (`DiagnosticsLog.redact`: JWT, chaves do Supabase e do atalho, `token=`/`apikey=`/`key=` e `Bearer`); o mesmo erro seguido conta uma vez.
- **Onde fica:** na Web, no `localStorage` (sobrevive a recarregar a página); no Android, só em memória.
- **Uso:** "Copiar tudo" põe o texto na área de transferência, para colar a quem ajuda. "Limpar erros" apaga a lista.

## Desempenho

Queries seletivas, índices orientados às consultas, imagens adequadas ao tamanho visível e listas preguiçosas. Pesquisa de combinações com orçamento explícito e instrumentação.

Trabalho CPU pesado usa isolates no nativo quando necessário. Na Web, medir e usar Web Worker quando justificado; `compute()` não garante outra thread.

## Crescimento

Preparar IDs, migrações e contratos claros. Não implementar já pagamentos, filas comerciais ou múltiplos microserviços.

Trocar um fornecedor não será “grátis”: auth, semântica de sync e migrações exigem trabalho, mas não devem obrigar a reescrever regras de outfits.
