# Feature — Estação, meteorologia e conforto

Estado: necessária no MVP do motor.

## Contexto inicial

Torres Vedras/região de Lisboa, com localização escolhida manualmente. Não exigir GPS nem localização contínua.

O mês/estação ajuda a contextualizar, mas a decisão usa previsão: temperatura, sensação térmica quando disponível, chuva, vento e horizonte temporal.

## Implementação recomendada

Open-Meteo através de `http`, com cache local por localização/data, timestamp e atribuição visível.

`WeatherRepository` devolve previsão e frescura, não só números. O domínio combina condições com aquecimento/cobertura conhecidos, camadas e preferências de conforto.

Coordenadas aproximadas da cidade são suficientes inicialmente. Cache e pedidos devem minimizar dados e chamadas.

## Comportamento

1. Escolher cidade e fuso no onboarding.
2. Consultar previsão ao preparar o planeamento, respeitando cache.
3. Distinguir previsão recente, antiga e ausente.
4. Permitir um contexto manual identificado quando não há rede/previsão.
5. Atualizar contexto ao abrir a app.
6. Se uma alteração afetar um plano aceite, avisar e propor substituição.

Não garantir previsão diária precisa fora do horizonte do fornecedor. Não usar uma média sazonal como se fosse uma previsão.

## Regras

Não converter “verão” numa proibição cega de casacos nem “inverno” numa obrigação universal de camadas.

Uma t-shirt como top único é válida quando o contexto e preferências o permitem. Uma composição com camadas pode permitir adaptação; não significa que todas as camadas sejam obrigatórias.

Limites pessoais de frio/calor precisam de calibração e override. Não anunciar uma medida científica de conforto ainda não validada.

## Alternativas

| Opção | Avaliação |
|---|---|
| Open-Meteo pessoal | Recomendado: sem chave obrigatória para o uso gratuito atual |
| Apenas estação/mês | Funciona offline, mas demasiado impreciso como regra principal |
| GPS obrigatório | Mais automático, mas desnecessário e com permissões/privacidade |
| API paga de meteorologia | Rever quando houver uso comercial ou requisitos adicionais |
| Meteorologia manual | Alternativa legítima, explicitamente marcada como manual |

## Custos e licença

O endpoint gratuito é para uso não comercial e tem atribuição/limites. A licença CC BY dos dados não é, por si só, uma proibição de uso comercial; as condições de acesso gratuito à API são uma questão distinta.

Subscrições/publicidade exigem rever o serviço antes de lançar. Ver [custos](../custos-e-limitacoes.md) e [fontes](../fontes.md).

## Ações e aceitação

O utilizador escolhe cidade e ajusta conforto. GPS e uma conta meteorológica não são pré-requisitos.

E2E-07 e E2E-09 do [plano](../plano-e2e.md): condições frias/quentes/chuva, cache offline com aviso, ausência de previsão e alteração proposta sem aplicação automática.
