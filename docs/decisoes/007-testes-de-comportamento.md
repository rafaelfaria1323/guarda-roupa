# ADR-007 — Testes orientados a comportamento real

Estado: objetivo confirmado; ferramentas e execução multiplataforma a validar.

## Contexto

O utilizador quer confiança no uso real, não métricas de coverage inflacionadas. São relevantes UI, picker, persistência de fotos, offline, sincronização e PWA instalada no iPhone.

## Alternativas

| Opção | Benefícios | Limitações | Decisão |
|---|---|---|---|
| Patrol | Flutter + ações nativas; Web/Chromium documentado | Configuração própria e POC; não comprova iPhone PWA por si só | Candidato recomendado |
| `integration_test` | Ferramenta oficial Flutter | Interações externas/nativas requerem outras soluções | Usar onde suficiente |
| Playwright Web isolado | Browser, downloads e rede | Selecionar conteúdo Flutter renderizado pode ser difícil; não cobre Android nativo | Complementar |
| Appium | Automação multiplataforma e UI externa | Mais infraestrutura e manutenção | Não adicionar sem lacuna concreta |
| Só widget/unit tests | Rápidos e determinísticos | Não provam persistência/plataforma/sync real | Necessários, insuficientes |
| Só guião manual | Valida aparelho real | Regressão repetitiva e menos automatizável | Complemento, não estratégia única |

## Escolha proposta

Testes focados para regras e transações; Patrol em jornadas Android/Chromium se a POC for aprovada; guião reproduzível no iPhone instalado.

A documentação Web primária do Patrol descreve Chromium com Playwright. Não inventar execução `--device webkit` nem apresentar um browser desktop como prova equivalente ao iPhone.

## O que pode ser controlado

Relógio, seed e respostas externas em cenários identificados. Nestes testes, manter UI, motor, repositórios e armazenamento reais.

Separar teste contra resposta meteorológica controlada de smoke contra API real. Ficar verde com um mock não prova disponibilidade da integração.

## O que mede sucesso

Resultado observável, dados persistidos após reabrir, comportamento negativo e ausência de efeitos indevidos. Não verificar apenas se um método foi chamado.

Não esconder flakes com retries automáticos. Investigar causa e guardar evidência; uma segunda tentativa não transforma o erro original em inexistente.

## Consequências

Testes reais são mais lentos e precisam de contas/dados isolados. Executar os menores conjuntos relevantes por alteração e manter uma matriz por plataforma.

Evidência manual pode ser aceite para gaps explícitos, com hardware/versão/passo/resultado registados.

Guias: [testes](../guidelines/testes.md), [plano E2E](../plano-e2e.md), [execução](../guias/06-executar-validacoes.md). Fontes oficiais: [registo](../fontes.md).
