# ADR-001 — Flutter, Android e PWA

Estado: Flutter e plataformas iniciais confirmados; detalhes de distribuição/compatibilidade a validar.

## Contexto

O utilizador desenvolve Flutter, utiliza Android e pretende acesso no iPhone sem depender de publicação nativa paga. Há lógica complexa partilhável e não é um site de conteúdo dependente de SEO.

## Alternativas

| Opção | Benefícios | Custos/limitações | Decisão |
|---|---|---|---|
| Flutter Android + Web/PWA | Uma base de UI/domínio, conhecimento existente, sem publicação iOS inicial | Persistência/browser, bundle e ficheiros precisam de POC | Escolhida como direção |
| Flutter Android + iOS nativo | Melhor integração nativa e distribuição convencional | Setup Apple, assinatura/publicação e manutenção adicional | Adiado |
| React Native/Expo + Web | Ecossistema válido e partilha parcial | Troca de stack sem benefício demonstrado; diferenças Web mantêm-se | Não escolhido |
| Android e iOS separados | Máxima adaptação por plataforma | Duas UIs e mais esforço | Desproporcional |
| Web tradicional responsiva | Bundle/DOM e integração Web potencialmente melhores | Outra stack para o Android nativo pretendido | Alternativa se Flutter Web falhar os gates |

## Consequências

Regras do domínio não dependem de widgets. Ficheiros, permissões e persistência usam adaptadores de plataforma.

Não afirmar equivalência entre PWA e app nativa. A PWA depende de HTTPS, cache preparada e políticas de armazenamento do browser.

Não exigir execução em segundo plano com a PWA fechada. Este limite é compatível com o requisito confirmado.

## Distribuição

APK pessoal Android com chave própria preservada. PWA em `pages.dev`, sem domínio comprado obrigatório. iPhone instala pelo Safari/ecrã principal.

Não existe app criada, SDK/OS mínimo aprovado ou publicação realizada.

## Rever quando

Integrações nativas indispensáveis, limites reais do Safari, necessidade de App Store ou pior desempenho comprovado do Flutter Web. Uma nova plataforma não deve obrigar a reescrever regras de conjuntos.

## Evidência e ações

Fontes: Flutter Web FAQ, setup Android e WebKit em [Fontes](../fontes.md).

Gates: P-05, P-09 e P-15. Guias: [ambiente](../guias/01-ambiente-macos.md) e [instalação](../guias/05-instalar-android-e-pwa.md).
