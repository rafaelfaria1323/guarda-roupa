# Guidelines — Código, desempenho e escalabilidade

Estado: normas para a futura implementação. Repository Pattern e preocupação com desempenho/escalabilidade foram pedidos explicitamente.

## Regra principal

Escolher o approach mais simples que satisfaça corretamente o requisito e permita evolução. “Melhor” não significa mais abstrações, mais packages ou uma arquitetura empresarial prematura.

## Fronteiras obrigatórias

1. Widgets apresentam estado e enviam intenções.
2. Controllers/casos de uso coordenam a interação.
3. Domínio mantém regras de conjuntos, datas, rotação e cuidado.
4. Repositórios encapsulam operações e consistência.
5. Adaptadores tratam SQL, rede, ficheiros e plataforma.

Não aceder a Drift, Supabase, HTTP ou filesystem diretamente num widget. Não expor linhas SQL/DTOs cloud como entidades da apresentação.

Interfaces orientadas ao negócio; sem `BaseRepository<T>` universal. Transações que abrangem várias entidades não são montadas pelo ecrã através de chamadas soltas.

## Organização e legibilidade

Feature-first, nomes do domínio e tipos pequenos. Dart puro para regras reutilizáveis. IDs e enums estáveis; texto localizado apenas na apresentação.

Evitar booleanos ambíguos, `dynamic`, casts forçados, null assertions e mapas sem schema para dados centrais. Modelar estados/erros impossíveis de confundir.

Não comentar o óbvio. Documentar decisões não evidentes, constraints e razões de implementação. Atualizar feature/ADR quando o comportamento aprovado mudar.

Usar recursos nativos de Dart antes de adicionar dependências de geração/imutabilidade sem necessidade.

## Estado e concorrência

Riverpod compõe dependências; observar apenas o estado necessário ao componente. Não duplicar todo o catálogo em vários providers.

Separar estado persistido, estado de sync e estado transitório da UI. Impedir que uma resposta antiga de pesquisa substitua a mais recente.

Cancelar operações quando apropriado, mas não descartar uma mutação já confirmada localmente por o utilizador sair do ecrã.

Não depender de `dispose` ou de um evento de fecho para guardar dados essenciais.

## Persistência e consistência

- Queries seletivas, relações/constraints e transações.
- Índices derivados de consultas reais; evitar N+1.
- Atualizações de domínio + outbox atómicas quando o protocolo próprio for escolhido.
- Migrações versionadas e testadas com dados antigos.
- Nada de apagar/recriar a base para resolver uma migração em produção.
- Assets com staging e referências consistentes; limpeza apenas de órfãos identificados.

Não usar um único JSON gigante para contornar o modelo relacional.

## Erros explícitos

Classificar validação, cancelamento, rede, autorização, quota, conflito e corrupção. Devolver resultados tipados e mensagens úteis.

Proibido capturar tudo e devolver `[]`, `null`, uma previsão neutra ou sucesso fictício. Fallback manual é válido se a sua origem/limitação for visível.

Retry com limite/backoff e operações idempotentes. Não repetir infinitamente uma violação de autorização ou dados inválidos.

## Desempenho

| Superfície | Norma |
|---|---|
| Catálogo | Miniaturas, listas preguiçosas e consultas filtradas |
| Estado visual | Rebuilds localizados; medir antes de otimizar |
| Fotos | Validar dimensões, limitar memória e não descodificar originais em cada rebuild |
| Motor | Filtrar/podar, orçamento de pesquisa e contadores de expansão |
| Rede | Cache com validade explícita, payloads limitados e pedidos deduplicados quando necessário |
| Sync | Lotes limitados, retomada e backpressure para uploads |
| Backup | Orçamento de memória e validação antes de aplicar |

No nativo, isolates para CPU pesada quando compensar. Na Web, confirmar workers reais; `compute()` não garante trabalho fora da thread da UI.

Não prometer desempenho apenas porque existe Repository Pattern. Definir hardware e budgets em P-09 e medir em profile/release, registando dados e condições.

## Datas e eventos

Planeamento usa datas de calendário e fuso; eventos usam UTC e contexto local. Não tratar “três dias” como sempre 72 horas.

Planeado, reservado e utilizado são estados distintos. Eventos confirmados/corrigidos devem manter projeções consistentes.

T-shirt não implica layer. Recomendação de lavar não implica indisponibilidade. Estas regras não podem divergir entre UI, gerador e sync.

## Privacidade e configuração

Autorização no servidor e Storage privado desde o início. Nunca incluir secrets, tokens de sessão ou chave de assinatura no repositório, logs, backups ou assets Web.

`--dart-define` e ficheiros `.env` incluídos no cliente não escondem segredos. Chaves publicáveis são configuração pública, não autorização.

Logs mínimos, sem fotografias, dados de conta ou URLs com tokens. Não introduzir analytics/telemetria de terceiros por defeito.

## Dependências, revisão e entrega

Verificar manutenção, licença, tamanho, suporte real Android/Web e interação com a stack. Adicionar apenas no incremento necessário; commit do lockfile da aplicação.

Usar formatter, analyzer e testes existentes. Rever diffs e alterações geradas. Não introduzir tooling pesado só para fazer o projeto parecer preparado para escala.

Antes de concluir: comportamento implementado em todas as superfícies relevantes, erros tratados, migração segura, documentação relacionada atualizada e cenário real demonstrável.

Referências: [arquitetura](../arquitetura.md), [modelo](../modelo-de-dados.md), [guidelines de testes](testes.md).
