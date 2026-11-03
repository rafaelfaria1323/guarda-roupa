# ADR-002 — Repository Pattern, estado e dados locais

Estado: Repository Pattern confirmado; bibliotecas recomendadas, dependentes da POC.

## Decisão

Feature-first, domínio em Dart puro, contratos orientados ao negócio e implementação de dados encapsulada. Riverpod para estado/DI, go_router para navegação e Drift/SQLite para dados locais.

Não confundir “usar Repository Pattern” com criar um wrapper genérico para cada chamada SQL.

## Estado e dependências

| Opção | Benefícios | Trade-off | Escolha |
|---|---|---|---|
| Riverpod | DI, estado assíncrono e composição testável | Disciplina para não colocar domínio nos providers | Recomendado |
| BLoC/Cubit | Fluxos/eventos explícitos e padrões maduros | Mais estrutura para este produto; igualmente válido se a equipa o preferir | Alternativa |
| Provider/ChangeNotifier | Simples e conhecido | Estados/concorrência exigem disciplina adicional | Viável, não preferido |
| `setState` globalmente | Poucas dependências | Não organiza dependências e sync do produto | Só estado visual local |
| Framework integrado de UI/DI/rotas | Menos decisões iniciais | Maior acoplamento e convenções desnecessárias | Não necessário |

Não se presume que Riverpod é automaticamente mais rápido do que BLoC. Desempenho depende da implementação.

## Persistência

| Opção | Benefícios | Trade-off | Escolha |
|---|---|---|---|
| Drift/SQLite | Relações, transações, queries tipadas e observação | Migrações e setup Web/WASM | Recomendado |
| `sqflite` + adaptadores | SQL direto e conhecido | Mais trabalho tipado, observação e Web | Não preferido |
| Hive/Isar/alternativas de objetos | Simplicidade para certos modelos | Relações/histórico e manutenção/Web da versão a confirmar | Não selecionado |
| SharedPreferences/localStorage | Bom para pequenas preferências | Sem integridade adequada ao inventário e histórico | Não usar como base |
| Apenas base cloud | Menos schema local inicial | Não satisfaz offline robusto | Rejeitado |

Se PowerSync for escolhido, usar a integração Drift suportada sobre a conexão gerida pelo SDK. Não manter duas bases locais concorrentes.

**Atualização (2026-11-03):** com PowerSync escolhido, o primeiro incremento usa SQL direto (`sqlite_async`) dentro de `PowerSyncWardrobeRepository`; Drift fica adiado até o schema justificar queries tipadas. O contrato `WardrobeRepository` não muda com essa troca.

## Navegação

`go_router` permite URLs, redirects de sessão e layout responsivo. Navigator manual continua apropriado para fluxos locais simples, mas manter toda a navegação declarativa à mão acrescenta trabalho.

Não resolver autorização só com redirects de UI.

## Custos, licenças e versões

As bibliotecas propostas não introduzem faturação por utilização. Isto não substitui a verificação de licença da versão concreta e de dependências transitivas.

No bootstrap: escolher SDK, resolver packages, registar licenças e commit do lockfile. Dependências ainda não foram instaladas/validadas.

## Consequências e revisão

Mais disciplina de fronteiras e migrações em troca de regras reutilizáveis e comportamento previsível. Não criar abstrações para fornecedores hipotéticos; extrair quando há necessidade real.

Rever biblioteca se POC Web/sync falhar ou manutenção deixar de ser adequada.

Fontes: Drift/package docs em [Fontes](../fontes.md). Norma: [Guidelines](../guidelines/codigo-e-arquitetura.md).
