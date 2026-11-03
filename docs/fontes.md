# Fontes e âmbito da consulta

Data de referência: 2026-10-31. Os textos deste dossier são síntese e decisões próprias, não cópias de documentação de fornecedores.

Complemento em 2026-11-02: consultadas diretamente as instruções Cloudflare de integração Git e Flutter de assinatura Android para concluir os guias. As restantes condições mantêm a data de referência indicada, salvo nota explícita.

Preços, interfaces e versões são mutáveis. Antes de executar uma configuração ou monetizar, voltar a confirmar a fonte oficial.

## Fontes primárias consultadas

| Tema | Fonte | Utilização |
|---|---|---|
| Flutter Web, browsers e service worker | https://docs.flutter.dev/platform-integration/web/faq | Offline não é configurado automaticamente nas versões recentes |
| Flutter Android | https://docs.flutter.dev/platform-integration/android/setup | SDK Manager, Device Manager, licenças e ligação |
| Flutter integration tests | https://docs.flutter.dev/testing/integration-tests | Capacidades e execução da base Flutter |
| Drift setup | https://drift.simonbinder.eu/setup/ | Dependências, base e geração |
| Drift Web | https://drift.simonbinder.eu/platforms/web/ | WASM, workers, fallbacks e headers |
| Armazenamento WebKit | https://webkit.org/blog/14403/updates-to-storage-policy/ | Quotas, eviction e pedido de persistência |
| Captura de imagens | https://pub.dev/packages/image_picker | Cache temporária, recuperação Android e plataformas |
| Captura Web | https://pub.dev/packages/image_picker_for_web | Capture é dependente do browser; bytes versus blob URL |
| Tratamento de imagem | https://pub.dev/packages/image | Formatos, transformações e processamento Web na thread principal |
| Recorte | https://pub.dev/packages/crop_your_image | Widget de recorte, não leitor/armazenamento de ficheiros |
| IndexedDB | https://pub.dev/packages/idb_shim | Alternativa de persistência de bytes na Web |
| Seleção de ficheiros | https://pub.dev/packages/file_selector | `getSaveLocation` não é universal; seleção suportada |
| Exportação | https://pub.dev/packages/file_saver | Distinguir save privado, saveAs e download |
| ONNX Flutter | https://pub.dev/packages/flutter_onnxruntime | Plataformas e dependência de runtime Web |
| ONNX Web | https://onnxruntime.ai/docs/get-started/with-javascript/web.html | CPU/WASM e diferenças de aceleração |
| Open-Meteo | https://open-meteo.com/en/terms | Uso não comercial, atribuição e limites |
| Supabase Free | https://supabase.com/pricing | Base, ficheiros, egress, pausa e ausência de backup automático Free |
| Supabase Flutter | https://supabase.com/docs/guides/getting-started/quickstarts/flutter | Projeto, cliente Flutter e Connect |
| API keys Supabase | https://supabase.com/docs/guides/getting-started/api-keys | Publishable/secret e diferença entre chave e identidade |
| OAuth Google Supabase | https://supabase.com/docs/guides/auth/social-sign-in/auth-google | Google Auth Platform, callback e configuração |
| SMTP Supabase | https://supabase.com/docs/guides/auth/auth-smtp | Endereços autorizados e limite padrão de emails |
| Storage buckets | https://supabase.com/docs/guides/storage/buckets/creating-buckets | Dashboard, New Bucket e restrições |
| Firebase Storage | https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024 | Blaze obrigatório com possibilidade de quotas sem custo |
| Pages limites | https://developers.cloudflare.com/pages/platform/limits/ | Builds, ficheiros e limite de 25 MiB |
| Pages Direct Upload | https://developers.cloudflare.com/pages/get-started/direct-upload/ | Navegação e diferença entre drag-and-drop/Wrangler |
| Pages Git integration | https://developers.cloudflare.com/pages/get-started/git-integration/ | Consulta em 2026-11-02: autorização, campos de build, origens e deploys |
| Workers preços | https://developers.cloudflare.com/workers/platform/pricing/ | Free: pedidos e CPU |
| HTMLRewriter | https://developers.cloudflare.com/workers/runtime-apis/html-rewriter/ | Extração leve de HTML |
| Patrol | https://patrol.leancode.co/documentation | Setup, configuração e limitações |
| Patrol Web | https://patrol.leancode.co/documentation/web | Chromium/Playwright, uploads e downloads |
| PowerSync Free | https://powersync.com/pricing | Plano gratuito atual e discrepância no prazo de inatividade |
| Cuidados de lavagem | https://extension.usu.edu/news_sections/home_family_and_food/the-dirt-on-laundry-how-often-to-wash | Orientações por categoria atribuídas ao ACI |
| Assinatura Android | https://docs.flutter.dev/deployment/android | Consulta em 2026-11-02: keystore, propriedades, Gradle, assinatura debug/release e manifest |

## Referências adicionais a confirmar na fase correspondente

| Tema | Referência | Limitação da evidência |
|---|---|---|
| PWA no iPhone | https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios | Instruções localizadas por pesquisa; páginas anteriores e nova tentativa direta em 2026-11-02 devolveram 429. Confirmar labels/versão no dispositivo |
| Pinterest | https://developers.pinterest.com/docs/api/v5/ | Não foi confirmado acesso a um Pin arbitrário a partir de documentação primária de endpoint |
| Pinterest OAuth | https://developers.pinterest.com/docs/getting-started/set-up-authentication-and-authorization/ | Acesso efetivo/tier a confirmar; não garantir importação universal |
| Produto estruturado | https://schema.org/Product | Campos possíveis não implicam presença em todas as lojas |
| CORS | https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS | Referência de restrições do browser |
| PowerSync Flutter | https://docs.powersync.com/client-sdks/overview | Integração exata Drift/Safari deve ser demonstrada na POC |
| ACI | https://www.cleaninginstitute.org/cleaning-tips/clothes/laundry-basics/do-i-need-wash | Acesso direto devolveu 403; não atribuir números não verificados a esta página |
| Row Level Security | https://supabase.com/docs/guides/database/postgres/row-level-security | Regras concretas dependem do schema implementado |
| Flutter instalação | https://docs.flutter.dev/install/manual | Escolher macOS e arquitetura reais antes de instalar |

## Observações importantes

O resumo de pesquisa secundária sobre Patrol sugeriu browsers e comandos que não ficaram confirmados na página primária. Por isso, este dossier só recomenda o comando Web/Chromium documentado e não apresenta uma execução Safari como resolvida.

A página PowerSync apresenta um Free tier atualmente e prazos de desativação inconsistentes entre secções. O plano não foi ignorado, mas também não é tratado como ilimitado ou aprovado.

A orientação de lavagem da USU é uma referência geral, não uma garantia de higiene nem instrução para pôr qualquer tecido na máquina.

Nenhuma destas consultas demonstra que a futura aplicação já passou os cenários de compatibilidade.
