# Feature — Guarda-roupa e peças

Estado: necessária no MVP. Implementação recomendada nos incrementos 1–2.

Implementado (2026-11-03): criar/editar/duplicar/arquivar/eliminar (tombstone, com confirmação e limpeza das fotos), disponibilidade, pesquisa sem acentos, filtros por grupo de categoria e disponibilidade, cores de uma paleta de referência com proporção aproximada (passos de 10%, soma ≤ 100%, confirmadas pelo utilizador; podem ser sugeridas pela foto e ficam marcadas até confirmar, ver [fotografias](fotografias-e-ficheiros.md)) e fotografias. Detalhes opcionais (secção “Detalhes”; nada escolhido = “não sei”): padrão, textura superficial, aquecimento, adequação a chuva e vento (sim/não/não sei), ocasiões iniciais (casual, trabalho (smart casual), noite/saída; também como filtro da lista) e material/cuidados como texto da etiqueta. Por fazer: composição estruturada (percentagens por fibra) e símbolos de cuidados.

## Objetivo e dados

Representar peças físicas, não apenas produtos comerciais. Cada unidade tem ID, categoria, disponibilidade, histórico e fotografias próprios.

Campos progressivos:

| Grupo | Informação |
|---|---|
| Identificação | Nome opcional, categoria, marca/origem opcionais |
| Aparência | Cores e proporções, padrão, textura superficial |
| Contexto | Ocasiões, aquecimento/cobertura, adequação conhecida a chuva/vento |
| Composição | Material e cuidados quando conhecidos, preferencialmente pela etiqueta |
| Operação | Disponibilidade, arquivo, políticas específicas e imagens |

Padrão, textura e composição não são o mesmo atributo. “Malha” visível não prova percentagem de lã.

## Comportamento

1. Criar uma peça com informação essencial e completar depois.
2. Corrigir sugestões de categoria/cor antes ou depois de guardar.
3. Pesquisar/filtrar por categoria, disponibilidade e contexto.
4. Arquivar peças sem perder histórico.
5. Duplicar dados de uma peça semelhante, criando um novo ID e histórico vazio.
6. Mostrar dados guardados localmente e estado da sincronização.

Não exigir um número conhecido de peças nem impor um limite de 100. Uma peça sem dados suficientes pode existir no catálogo; o motor explica eventuais limitações para a usar.

## Tecnologia

Flutter/Material 3, Riverpod e repositório de guarda-roupa. Drift para queries/transações; Supabase e motor de sync se aprovados. As fotografias usam o [subsistema de media](fotografias-e-ficheiros.md).

Índices apenas para consultas usadas; miniaturas na grelha; paginação/carregamento incremental conforme o volume. Não carregar originais para preencher cartões pequenos.

## Alternativas e escolha

| Opção | Avaliação |
|---|---|
| Modelo relacional tipado | Recomendado: histórico, relações e queries consistentes |
| Documento JSON único por guarda-roupa | Simples no início, mas conflitos e atualizações amplas em sync |
| Formulário obrigatório muito extenso | Dados mais completos, mas manutenção pouco realista |
| Só fotografia e IA | Menos input inicial, mas erros/atributos desconhecidos; inadequado como única fonte |
| Scanner de código de barras | Depende de catálogo externo e variantes; adiado |

Ver [ADR-002](../decisoes/002-repositorios-estado-e-dados.md).

## Falhas e ações humanas

Peça sem fotografia pode usar placeholder identificado. Falha de guardar não pode resultar num cartão de sucesso. Falha do upload mantém estado pendente e possibilidade de retomar.

O utilizador confirma atributos que a app não conhece. Configurações externas só são necessárias na fundação: [ambiente](../guias/01-ambiente-macos.md) e [cloud](../guias/02-supabase-projeto-e-storage.md).

## Aceitação comportamental

E2E-01, E2E-11 e E2E-18 do [plano E2E](../plano-e2e.md): criar, editar, arquivar, reabrir, usar offline e sincronizar; duas unidades iguais mantêm históricos distintos; testar 10/50/100 peças sem transformar esses números em limites.
