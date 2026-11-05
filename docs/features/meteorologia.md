# Feature — Estação, meteorologia e conforto

Estado: necessária no MVP do motor.

## Decisões

- **Localização (P-18, 2026-11-03):** Torres Vedras com coordenadas aproximadas da cidade, fuso Europe/Lisbon, editável nas Definições. Sem GPS.
- **Conforto (P-17, 2026-11-03), aplicado a top, parte de baixo e peça única pelo aquecimento indicado:**
  - sensação ≥ 22 °C: peças leves; sem camadas;
  - 14–22 °C: peças médias ou leves; casaco como camada opcional;
  - < 14 °C: uma peça quente chega; uma leve ou média leva casaco (sem casaco, o conjunto fica parcial);
  - partes de baixo: o casaco não as cobre, por isso só os extremos não servem (quente no calor, leve no frio);
  - chuva ou vento ≥ 30 km/h: casaco e calçado marcados para chuva/vento à frente, marcados como não adequados atrás; no calor com chuva, um impermeável aparece como camada opcional;
  - aquecimento desconhecido nunca exclui: a peça entra com nota.

Implementado no motor (`lib/features/engine/domain/comfort.dart`). Os valores acima são os de origem. Editam-se em Definições › Conforto e tempo (`ComfortSettingsScreen`):

- calor de 15 a 35 °C e frio de 0 a 25 °C, de grau em grau; o frio fica sempre abaixo do calor, e os botões que o violariam ficam desativados;
- vento de 10 a 80 km/h, de 5 em 5;
- há um botão para repor os valores de origem.

Os limites ficam neste dispositivo (`local_settings`, chave `comfort_thresholds`, em JSON), como a localização: não sincronizam e não entram no backup. Um valor guardado inválido volta aos de origem. Aplicam-se às sugestões de hoje, à geração da semana e à revisão do plano (avisos de peça desadequada à previsão).

## Implementado (2026-11-03): previsão e localização

- **Localização:** Definições › Localização da meteorologia. Pesquisa por nome na geocodificação do Open-Meteo e escolha numa lista (nome, região, coordenadas). Guarda-se neste dispositivo (tabela local `local_settings`, fora da sincronização e do backup), com coordenadas arredondadas a duas casas decimais. Sem escolha, Torres Vedras (39,09; −9,26; Europe/Lisbon).
- **Pedido:** `api.open-meteo.com/v1/forecast` com coordenadas arredondadas, fuso do local, 7 dias e valores horários: sensação térmica, precipitação, probabilidade de precipitação e vento a 10 m (km/h). Não envia mais nada. Sem chave.
- **Resumo por dia** (`DayWeather`), só das 8 h às 20 h locais (a madrugada não conta):
  - média, mínimo e máximo da sensação térmica;
  - precipitação somada e probabilidade máxima;
  - vento máximo.
  - Um dia com horas em falta fica de fora.
- **Chuva para o motor** (`RainRule`): ≥ 1 mm nessas horas, ou probabilidade ≥ 50 %. São valores técnicos iniciais, a rever com o utilizador. O motor recebe a sensação média, a chuva e o vento máximo.
- **Cache** (`WeatherRepository`, tabela local `weather_cache` por local):
  - pede no máximo uma vez a cada 3 h, salvo pedido explícito para atualizar;
  - com menos de 6 h, a previsão é *recente*; uma cópia mais velha (sem rede ou pedido falhado) é *antiga* e diz quando foi obtida;
  - sem cópia é *ausente*, e o mesmo fora dos 7 dias;
  - mudar de local nunca usa a previsão de outro;
  - nunca se inventa uma previsão.
- **Atribuição:** "Dados meteorológicos: Open-Meteo.com" no ecrã da localização; também aparece onde a previsão for mostrada.
- **Testes:** usam um cliente HTTP falso e nunca vão à rede.

Mostrada e usada em "Sugestões para hoje" em Hoje (antes Planeador), com contexto manual identificado ([motor](motor-de-combinacoes.md)). Ainda não: o aviso quando uma previsão nova muda um plano aceite.

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
