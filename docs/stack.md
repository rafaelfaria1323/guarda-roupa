# Stack tecnológica

Estado: proposta técnica consolidada, com decisões de fornecedor e compatibilidade ainda sujeitas a aprovação e POC. Data: 2026-10-31.

## Base recomendada

| Área | Tecnologia | Motivo e estado |
|---|---|---|
| Cliente | Flutter + Dart stable | Preferência confirmada; partilha de lógica Android/Web |
| Interface | Material 3 personalizado | Recomendado: acessibilidade e adaptação sem framework visual pesado |
| Estado e DI | `flutter_riverpod` | Recomendado: estado assíncrono e dependências substituíveis |
| Rotas | `go_router` | Recomendado: navegação e URLs no browser |
| Dados locais | SQLite gerido pelo PowerSync (`powersync`, `sqlite_async`) | Em uso desde a POC: SQL direto dentro dos repositórios. `drift` adiado (ver abaixo) |
| Abertura da base | `drift_flutter` na opção Drift direta | Condicional à escolha do motor de sincronização |
| Cloud | Supabase Free | Recomendado, não aprovado: Auth, PostgreSQL, Storage privado |
| Cliente cloud | `supabase_flutter` | Condicional à aprovação do Supabase |
| Rede adicional | `http` | Meteorologia e importadores, sem cliente mais complexo inicialmente |
| Imagem | `image_picker`, `crop_your_image`, `image` | Captura, recorte e processamento |
| Ficheiros Android | `path_provider` | Armazenamento privado persistente |
| Ficheiros PWA | `idb_shim`/IndexedDB | Bytes persistentes; não guardar URLs `blob:` |
| Datas | `timezone`, `intl` | Fuso horário e datas de calendário |
| IDs | `uuid` | Identidade estável entre dispositivos |
| Serialização | `json_serializable` | DTOs de rede e formatos de backup explícitos |
| Geração | `build_runner`, `drift_dev` | Código gerado e schema local |
| Integridade | `crypto` | Hashes SHA-256; não equivale a encriptação |
| Backup | `archive`, `file_selector`, `file_saver` | ZIP, seleção e exportação efetiva |
| Traduções | `flutter_localizations`, ARB | PT-PT inicial, sem etiquetas localizadas na base |
| Meteorologia | Open-Meteo | Gratuito para uso pessoal não comercial, com atribuição |
| PWA | Cloudflare Pages + Workbox | Alojamento estático e cache offline explícita |
| Android | APK assinado com chave própria | Instalação pessoal sem publicação inicial na Play Store |

Não adicionar todos os packages no primeiro commit. Introduzir cada dependência no incremento que a utiliza.

## Decisão que pode alterar a abertura de SQLite

A POC escolheu PowerSync (P-03). Por agora os repositórios usam SQL direto sobre a base gerida pelo SDK (`sqlite_async`), sem Drift: menos geração de código e um só dono da base. Drift (integração `drift_sqlite_async`) volta a ser avaliado quando o schema crescer (conjuntos, histórico) e queries tipadas compensarem o custo. A troca fica contida nos repositórios. Não abrir `drift_flutter` e PowerSync como dois donos independentes da mesma base.

Se for escolhido um protocolo próprio, Drift mantém a base local e uma outbox transacional. O [ADR de sincronização](decisoes/004-sincronizacao.md) compara as duas opções.

## Motor de conjuntos

Dart puro, sem API generativa obrigatória:

1. Restrições de posse, disponibilidade, contexto e rotatividade.
2. Geração progressiva de candidatos completos.
3. Pontuação de cores, padrões/texturas, conforto, ocasião e preferências.
4. Pesquisa semanal limitada com diversidade e reservas.
5. Explicações estruturadas e exceções identificadas.

## Testes: recomendação atualizada

- `flutter_test` e, quando adequado, `integration_test` para testes focados e integração Flutter.
- **Patrol** como candidato recomendado a POC para jornadas Android e Flutter Web/Chromium, incluindo interações de plataforma.
- O suporte Web documentado do Patrol usa Playwright e Chromium. Não assumir uma flag de Safari/WebKit não confirmada.
- Safari/PWA instalada num iPhone real continua a exigir um percurso próprio de evidência; inicialmente pode ser um guião manual reproduzível.

Ver [ADR-007](decisoes/007-testes-de-comportamento.md).

## Etapas posteriores

| Necessidade | Direção |
|---|---|
| Importar produtos por link | Função TypeScript; Pages Functions proposta, Edge Functions como alternativa |
| IA local | `flutter_onnxruntime` e modelo ONNX por selecionar |
| Subscrições Web | Stripe Checkout/Billing e webhooks |
| Compras nativas | `in_app_purchase`, sujeito às regras das lojas |

## Versões e limites

As versões só serão fixadas depois de escolher o SDK e demonstrar a base Android/Web. Commitar `pubspec.lock` da aplicação e registar versões de CLI compatíveis.

Não foram gerados `pubspec.yaml`, código Flutter ou infraestrutura neste dossier. Custos e quotas encontram-se em [Custos e limitações](custos-e-limitacoes.md).
