# Produto e requisitos

Estado: requisitos confirmados e proposta de delimitação do MVP. Data: 2026-10-31.

## Visão

Uma aplicação pessoal que organiza o guarda-roupa e propõe conjuntos completos para a semana, utilizando exclusivamente peças possuídas. Combina disponibilidade, ocasião, meteorologia, preferências estéticas e rotatividade.

O objetivo não é maximizar o número de funcionalidades, mas reduzir a decisão diária e o trabalho de manter o inventário.

## Utilização inicial confirmada

| Tema | Requisito |
|---|---|
| Plataformas | Android nativo e Web/PWA, incluindo iPhone; outras plataformas no futuro |
| Dados | Mesma conta e sincronização automática entre dispositivos desde o início |
| Execução | Sincronização ao abrir, durante utilização online e ao recuperar ligação |
| Região inicial | Torres Vedras / região de Lisboa; cidade configurada manualmente |
| Ocasiões | Casual, trabalho (smart casual), jantares/saídas |
| Calendário | Um conjunto por dia inicialmente; vários por dia posteriormente |
| Histórico | Um toque para confirmar utilização; planeado não significa utilizado |
| Alterações | Avisar e propor; aplicar apenas depois de confirmação |
| Perfil (estilo) | Referências visuais e links com preferências assistidas inicialmente |
| Reutilização | Calçado e acessórios podem repetir; indisponibilidade continua a impedir utilização |
| Custos | Uso pessoal sem serviços pagos obrigatórios, respeitando quotas e limitações |
| Desenvolvimento | Flutter, Repository Pattern, código sustentável e testes de comportamento |

Não existe um máximo de 100 peças. Os conjuntos de 10, 50 e 100 peças são cenários representativos, não limites comerciais.

## Conceitos distintos

| Conceito | Significado |
|---|---|
| Peça | Uma unidade física possuída |
| Produto de loja | Informação comercial que pode ajudar a criar uma peça, após confirmação |
| Inspiração | Referência estética; não representa posse nem disponibilidade |
| Conjunto guardado | Composição reutilizável e categorizada |
| Conjunto planeado | Composição atribuída a uma data |
| Utilização | Evento real confirmado |
| Reserva | Utilização futura considerada pelo planeador, sem alterar o histórico real |
| Recomendação de lavagem | Aviso baseado numa política; não mede sujidade |

Duas t-shirts iguais continuam a ser duas peças. Podem ter a mesma fotografia (copiada para cada uma), mas nunca o histórico físico. A app mostra-as juntas e, ao registar, escolhe a que está há mais tempo sem uso ([peças iguais](features/guarda-roupa.md#peças-iguais)).

## Proposta de MVP utilizável

A fundação técnica isolada não é o MVP do produto. A primeira versão realmente útil deverá permitir:

1. Entrar na mesma conta em Android e na PWA.
2. Adicionar peças e fotografias e reencontrá-las nos dois dispositivos.
3. Organizar disponibilidade e confirmar utilizações.
4. Receber recomendações de lavagem e gerir os estados reais.
5. Criar e guardar conjuntos por ocasião.
6. Registar inspirações e preferências assistidas.
7. Gerar um conjunto diário e uma semana, com justificações e respeito pelas regras.
8. Alterar propostas, fixar escolhas e confirmar utilizações.
9. Trabalhar sem rede e sincronizar posteriormente com estado visível.
10. Exportar dados e seguir um procedimento de recuperação seguro.

Esta delimitação é uma recomendação de entrega. A ordem e os gates estão no [roadmap](roadmap.md).

## Fora da primeira versão

- Análise visual automática avançada ou identificação exata de produtos por fotografia.
- Importação garantida de qualquer loja ou qualquer Pin do Pinterest.
- Vários conjuntos por dia, integração automática com calendários e viagens.
- Provas virtuais, rede social, marketplace ou sugestões de compras.
- Contas comerciais, pagamentos e subscrições.
- Apps nativas iOS/desktop e funcionamento garantido em todos os browsers antigos.

Guardar um link de origem pode existir antes de o respetivo importador automático.

## Regras inegociáveis

- Nunca inventar peças para completar um conjunto.
- Nunca sugerir como disponível uma peça conhecida como suja, em lavagem ou a secar.
- Nunca converter reservas em utilizações reais.
- Nunca considerar silêncio como confirmação ou como desagrado estético.
- Nunca alterar silenciosamente conjuntos já aceites.
- Nunca assumir uma lavagem futura não confirmada.
- Nunca tratar t-shirt como categoria exclusiva de camada inferior.
- Nunca afirmar que uma fotografia revela com certeza material, composição ou aquecimento.
- Nunca esconder falhas de sincronização atrás de um indicador de sucesso.
- Nunca prometer frescura de dados de outro dispositivo enquanto se está offline.

## Comportamento quando faltam opções

A app explica a causa: peças indisponíveis, ausência de um papel obrigatório, intervalo de repetição ou falta de atributos essenciais.

As exceções só usam políticas autorizadas. Não existir uma solução encontrada dentro do orçamento de pesquisa não prova que nenhuma combinação exista. O motor pode alargar a pesquisa ou devolver um resultado parcial identificado.

## Critério de qualidade do produto

As features devem ser demonstradas através de percursos reais e resultados persistidos. Coverage é um indicador auxiliar. A estética será avaliada também por feedback humano: nenhuma fórmula prova universalmente que um conjunto é bonito.

Ver [Plano E2E](plano-e2e.md), [Custos](custos-e-limitacoes.md) e [Pendências](pendencias.md).
