# Planeamento da aplicação de guarda-roupa

Data de referência: **31 de outubro de 2026**. Idioma: português de Portugal.

Exportação documental: **2 de novembro de 2026**. As datas de consulta e limitações das fontes estão em [Fontes](fontes.md); a exportação não atualiza automaticamente as condições dos serviços.

Este dossier reúne o planeamento funcional e técnico discutido. Não contém uma aplicação implementada, recursos cloud criados ou resultados de testes da aplicação.

## Começar por aqui

1. Ler [Produto e requisitos](produto.md): o que está confirmado e o que pertence ao MVP.
2. Consultar [Stack tecnológica](stack.md) e [Arquitetura](arquitetura.md).
3. Ler o [Modelo de dados](modelo-de-dados.md) e o [Design e fluxos](design-e-fluxos.md).
4. Explorar as especificações de funcionalidades abaixo.
5. Seguir o [Roadmap incremental](roadmap.md), sem executar todos os passos de uma vez.
6. Antes de configurar serviços, ler [Custos e limitações](custos-e-limitacoes.md) e [Pendências](pendencias.md).

## Como interpretar o estado das decisões

| Estado | Significado |
|---|---|
| Confirmado | Requisito ou comportamento explicitamente escolhido pelo utilizador |
| Recomendado | Proposta técnica fundamentada, ainda não equivalente a aprovação ou prova de funcionamento |
| A validar | Necessita de decisão, experiência técnica ou confirmação das condições do fornecedor |
| Adiado | Fora da primeira versão; existe uma direção, não uma implementação |

Uma recomendação de package não é uma garantia de compatibilidade com todos os browsers. Custos, menus e APIs podem mudar; as [fontes](fontes.md) indicam o que foi consultado e as limitações da pesquisa.

## Especificações por funcionalidade

| Documento | Conteúdo |
|---|---|
| [Guarda-roupa](features/guarda-roupa.md) | Peças físicas, categorias, organização, pesquisa e atributos |
| [Fotografias e ficheiros](features/fotografias-e-ficheiros.md) | Captura, recorte, tratamento, persistência e ficheiros privados |
| [Conjuntos e ocasiões](features/conjuntos-e-ocasioes.md) | Conjuntos guardados, papéis das peças e classificações |
| [Utilização e rotatividade](features/utilizacao-e-rotatividade.md) | Confirmações, histórico, intervalos e alternativas |
| [Lavandaria](features/lavandaria.md) | Disponibilidade, recomendações de lavagem e secagem |
| [Meteorologia](features/meteorologia.md) | Estação, previsão, conforto e funcionamento sem rede |
| [Motor de combinações](features/motor-de-combinacoes.md) | Regras, cores, padrões, texturas, pontuação e explicações |
| [Planeamento semanal](features/planeamento-semanal.md) | Pesquisa conjunta da semana, reservas e propostas de alteração |
| [Inspirações e estilo](features/inspiracoes-e-estilo.md) | Referências visuais e preferências assistidas |
| [Autenticação e sincronização](features/autenticacao-e-sincronizacao.md) | Conta, dois dispositivos, offline, conflitos e dados privados |
| [Importação de links](features/importacao-de-links.md) | Produtos de lojas, metadados, variantes e limitações |
| [Backups e recuperação](features/backups-e-recuperacao.md) | Exportação, integridade e recuperação sem perda silenciosa |
| [IA local](features/ia-local.md) | Evolução opcional, modelos e limites de inferência |
| [Subscrições e evolução](features/subscricoes-e-evolucao.md) | Futuro comercial, pagamentos e custos |

## Decisões arquiteturais

As alternativas transversais têm a justificação principal nos ADRs, evitando copiar a mesma análise para todas as features.

1. [ADR-001 — Plataformas e Flutter](decisoes/001-plataformas.md)
2. [ADR-002 — Repository Pattern, estado e dados locais](decisoes/002-repositorios-estado-e-dados.md)
3. [ADR-003 — Backend e autenticação](decisoes/003-backend-e-autenticacao.md)
4. [ADR-004 — Sincronização local-first](decisoes/004-sincronizacao.md)
5. [ADR-005 — Motor de recomendação](decisoes/005-motor-de-recomendacao.md)
6. [ADR-006 — Ficheiros, PWA e recuperação](decisoes/006-ficheiros-pwa-e-backups.md)
7. [ADR-007 — Testes de comportamento](decisoes/007-testes-de-comportamento.md)
8. [ADR-008 — Conflitos, sessões e privacidade](decisoes/008-conflitos-e-privacidade.md)

## Guidelines e verificação do produto

- [Código e arquitetura](guidelines/codigo-e-arquitetura.md): Repository Pattern obrigatório, desempenho e evolução sustentável.
- [Testes](guidelines/testes.md): comportamento observável, fluxos reais e limites dos mocks.
- [Plano E2E](plano-e2e.md): cenários, plataformas e resultados esperados.

## Guias das ações do utilizador

Não é necessário executar estes guias todos agora. Cada um identifica o incremento em que se aplica, os pré-requisitos, o responsável e onde parar.

1. [Preparar o ambiente macOS](guias/01-ambiente-macos.md)
2. [Criar projeto e Storage no Supabase](guias/02-supabase-projeto-e-storage.md)
3. [Configurar login e variáveis públicas](guias/03-login-e-configuracao.md)
4. [Publicar a PWA](guias/04-publicar-pwa.md)
5. [Instalar Android e PWA no iPhone](guias/05-instalar-android-e-pwa.md)
6. [Executar cenários de validação](guias/06-executar-validacoes.md)
7. [Operação, backups e limites](guias/07-operacao-backups-e-limites.md)
8. [Preparar o servidor para a POC de sincronização](guias/08-poc-sincronizacao.md)

## Alterações importantes relativamente às primeiras propostas

- A sincronização Android/PWA é necessária **desde a primeira versão**, não apenas numa futura fase comercial.
- Sincronizar ao abrir e enquanto a aplicação está em utilização é suficiente; não prometemos execução contínua com a PWA fechada.
- O estilo começa por referências e preferências assistidas. A interpretação visual automática fica para depois.
- Alterações ao planeamento são propostas e só aplicadas com confirmação.
- Apenas utilizações confirmadas contam para histórico e lavagem.
- Atingir uma recomendação de lavagem não torna uma peça automaticamente indisponível.
- Uma t-shirt pode ser a única peça principal da parte de cima. Categoria não determina um papel fixo de layer.
- Calçado e acessórios podem repetir para este utilizador, desde que disponíveis.

## Limites deste documento

Ainda não foram executadas provas de compatibilidade da aplicação, criadas contas ou aprovados todos os fornecedores. O motor de sincronização, os valores iniciais de algumas políticas e as integrações de lojas permanecem sujeitos aos gates de [Pendências](pendencias.md). Estes estados não devem ser transformados em “concluído” apenas porque o planeamento está escrito.
