# Guidelines — Testar comportamento, não coverage

Estado: orientação confirmada; suites da aplicação ainda não existem.

## Objetivo

Provar que uma pessoa consegue executar os percursos com resultados corretos, persistentes e sem efeitos indevidos. Coverage não é meta principal nem substitui estes resultados.

## Camadas complementares

| Tipo | Papel |
|---|---|
| Testes de domínio | Regras, datas, constraints, pontuação e casos extremos |
| Integração de dados | SQL real, transações, migrações, media e protocolo |
| Widget | Estados, formulários, navegação local e acessibilidade |
| E2E | Fluxo por UI com motor, repositórios e persistência reais |
| Smoke de serviço real | Confirmar acesso/contrato externo sem confundir com testes controlados |
| Dispositivo real | Validar picker, browser, instalação, ciclo de vida e armazenamento |

E2E não elimina testes focados. Estes localizam falhas e exploram casos que seriam demasiado lentos por UI.

## Critérios para uma jornada real

- Ações semelhantes às do utilizador, por controlos reais.
- Persistência verdadeira, não um repositório em memória disfarçado.
- Gerador e políticas reais, não uma lista pronta de outfits.
- Verificação do resultado visível e dos efeitos importantes.
- Reabertura/relogin quando é a persistência que está em causa.
- Casos negativos e cancelamentos, não só happy path.

Pré-condições volumosas podem ser preparadas por fixture/script isolado, mas o percurso sob teste não pode contornar as camadas cujo comportamento se quer demonstrar. O teste de adicionar uma peça deve adicioná-la pela UI.

## Controlo e mocks

Permitir relógio/seed controláveis e respostas meteorológicas/de lojas fixas em cenários identificados. Nestes testes, manter o resto do fluxo real.

Complementar com smoke contra o serviço real. Um mock com JSON-LD não demonstra que a Zara continua a permitir o acesso.

Não simular o próprio repositório no teste que afirma validar base/sync. Não chamar diretamente o engine no teste que afirma validar o percurso de geração pela UI.

## Dados, isolamento e evidência

Contas, projetos e ficheiros de experiência sem peças pessoais. Cada teste tem preparação e limpeza explícitas. Nunca limpar uma conta real para garantir isolamento.

IDs únicos, seed registada e fuso conhecido. Cenários de mudança de hora devem usar datas concretas e relógio controlado.

Guardar falha inicial, screenshot/log redigido, versões, passos e contexto. Evitar sleeps fixos; aguardar condições observáveis com timeout.

Retries não são cura para flakes. Se houver retry de diagnóstico, preservar a falha e não afirmar que nunca existiu.

## Seletores e manutenção

Preferir semântica, chaves estáveis e grupos identificados. Evitar coordenadas frágeis ou índices de listas sem significado.

Helpers/PageObjects podem reduzir repetição de interação; as asserções de comportamento continuam explícitas no teste. Não esconder sucesso/falha dentro de um helper genérico.

Usar os padrões do projeto Flutter, não transplantar convenções de suites Kotlin/JUnit de outro produto.

## Plataformas e limites

| Evidência | O que demonstra | O que não demonstra |
|---|---|---|
| Android emulator | Percurso na versão/configuração testada | Todos os aparelhos Android |
| Chromium desktop | Flutter Web e APIs nesse browser | Safari real |
| WebKit desktop/emulação | Aproximação a certos comportamentos Web | PWA instalada no iPhone |
| iPhone/PWA instalada | Percurso real naquele aparelho/OS | Todas as versões iOS |

Registar a matriz. O que não foi executado fica pendente.

## Execução incremental

Executar o menor conjunto que cobre a mudança. Alargar quando houver motivo: alteração transversal, migração, falha não localizada ou release.

Gate de release inclui cenários críticos de [Plano E2E](../plano-e2e.md), não uma percentagem arbitrária de coverage.

Guia operacional: [Executar validações](../guias/06-executar-validacoes.md).
