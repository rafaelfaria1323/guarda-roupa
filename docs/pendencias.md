# Pendências, riscos e provas de viabilidade

Criado a 2026-10-31, antes de haver código. Atualizado a 2026-11-12: a app está publicada e em uso no iPhone do utilizador; o que falta é confirmar em aparelho de forma organizada ([lista de 15 minutos](guias/10-verificar-no-iphone.md)).

Uma pendência não deve desaparecer por estar descrita em Markdown. Fechar apenas com decisão/evidência e data.

| ID | Tema e estado | Como fechar | Bloqueia |
|---|---|---|---|
| P-01 | Backend — **Decidido 2026-11-03: Supabase Free; projeto criado e em uso** | Fechado | — |
| P-02 | Login — **Decidido 2026-11-03: Google OAuth; configurado, o utilizador entra na PWA** | Fechado | — |
| P-03 | Sync — **Aprovado provisoriamente 2026-11-03: PowerSync + Supabase** (ligação e autenticação a funcionar; testes com dois perfis/dispositivos do [guia 08 §7](guias/08-poc-sincronizacao.md) por fazer) | Executar os testes do §7; se falharem, corrigir ou recorrer ao protocolo próprio | Uso real em dois dispositivos |
| P-04 | Conflitos e privacidade — **Decidido 2026-11-03: [ADR-008](decisoes/008-conflitos-e-privacidade.md)** | Validar na POC (passos 4–8) e E2E-04/11/14 | Uso da conta em dois dispositivos |
| P-05 | PWA/fotografias — **Implementado 2026-11-03 sem validação em aparelho** (JPEG/PNG/WebP; HEIC dá erro claro) | Demonstrar armazenamento persistente, quotas, HEIC e reabertura offline no iPhone | Onboarding real |
| P-06 | Rotatividade — **Decidido 2026-11-03:** mínimo de 3 dias entre usos para tops, 2 para partes de baixo (calças, saias, calções), sem intervalo para casacos, calçado e acessórios; preferir as menos usadas; editável por categoria e por peça; sem alternativa, sugerir na mesma com aviso claro (não é modo estrito) | **Implementado** (`RotationPolicy`, valores por categoria/peça); falta ligar ao motor de combinações | Motor com políticas reais |
| P-07 | Lavagem — **Decidido 2026-11-03:** referência USU/ACI, só informativa e editável: t-shirts, tops e roupa desportiva após cada uso; camisas e polos 2 usos; camisolas, calças, ganga, saias e vestidos 4 usos; casacos e calçado sem aviso. ~~Nunca muda a disponibilidade sozinha~~ **Mudado 2026-11-06:** ao confirmar o uso que chega ao limiar, a peça passa sozinha a “Precisa de limpeza”; só volta a Disponível com “Lavei hoje” ou à mão | **Implementado** (`LaundryPolicy`, limpezas, avisos e valores por categoria/peça) | Avisos iniciais |
| P-08 | Rotina — **Decidido 2026-11-03 (confirmação):** botão “Vesti hoje” no ecrã de hoje, escolher as peças (ou confirmar o plano) e guardar; corrigir e desfazer depois; ~~sem notificações por agora~~ (**2026-11-06:** lembretes opcionais por notificação, [lembretes](features/lembretes.md); falta experimentar no iPhone); planear nunca conta como uso. **Confirmado 2026-11-06:** o uso não se regista sozinho; sem “Vesti hoje” o dia conta como não usado. **Implementado** (registo, histórico, corrigir, desfazer). Dias/ocasiões por defeito do planeamento semanal por decidir | Decidir a rotina semanal com o planeador (incrementos 5–6) | MVP de utilização |
| P-17 | Conforto — **Decidido 2026-11-03 (proposta):** sensação térmica ≥ 22 °C peças leves; 14–22 °C peças médias (ou leves) com camada opcional; < 14 °C peças quentes, ou leve/média mais casaco; chuva ou vento ≥ 30 km/h preferem casaco e calçado marcados para chuva/vento. Editável mais tarde | **Implementado** no motor (`ComfortThresholds`, `ComfortRules`) e editável em Definições › Conforto e tempo, por dispositivo e sem sincronizar ([meteorologia](features/meteorologia.md)). Falta calibrar o que conta como "chuva" na previsão | Calibração pessoal |
| P-18 | Localização — **Decidido 2026-11-03:** Torres Vedras, coordenadas aproximadas da cidade, fuso Europe/Lisbon, editável nas Definições; Open-Meteo sem GPS | **Implementado** (localização nas Definições, previsão com cache); usada em "Sugestões para hoje" | Previsão real |
| P-19 | Semana e ocasiões — **Decidido 2026-11-04:** planear os 7 dias; dias úteis começam em “Trabalho (smart casual)” (o trabalho não pede roupa formal); sábado e domingo ficam “a decidir” (sem ocasião) e provisórios: pode não acontecer nada que peça essa roupa, e o dia pode ficar vazio. Um plano nunca conta como utilização (P-08) | **Dados implementados** (`plan_entries`, `apply_plan_operation`, regras `WeekPlanRules`); pesquisa semanal (`WeeklyPlanner`), ecrã “Esta semana” e mudanças posteriores (`PlanReview`) feitos; **2026-11-06:** a semana planeia-se sozinha (dias já aceites) e as trocas aplicam-se sozinhas com aviso e “Desfazer”; **2026-11-06:** formalidade por ocasião decidida e implementada (peças sem ocasiões: a noite pede casual cuidado ou arranjado; trabalho e dia a dia aceitam qualquer formalidade) | Semana utilizável |
| P-09 | Perfis e desempenho | Escolher dispositivos de referência e orçamento mensurável | Gate de desempenho |
| P-10 | Automação E2E | POC Patrol Android/Chromium; guião iPhone real, sem equivalência fictícia | Evidência por plataforma |
| P-11 | Recuperação com cloud — **Decidido 2026-11-06: juntar** (não substituir) | **Implementado:** acrescenta só o que falta, sem duplicar nem ressuscitar o que foi apagado ou desfeito; peças apagadas depois do backup só voltam se marcadas no preview ([backups](features/backups-e-recuperacao.md)). Falta ensaiar no aparelho (E2E-13) | Recuperação sobre conta existente |
| P-12 | Lojas suportadas — **Decidido 2026-11-04:** qualquer site público, com perfil por domínio que se atualiza sozinho (antes: Zara, Uniqlo, Pull&Bear e Bershka); função em Supabase Edge Functions | **Função e fluxo na app feitos; função publicada a 2026-11-04**; [smoke](../tool/import/README.md) com links reais feito na cloud a 2026-11-06 (Uniqlo `ok`; H&M, Mango, Levi’s e Decathlon bloqueiam; resultados em [importação](features/importacao-de-links.md)). **Teste do utilizador a 2026-11-05 na PWA:** Uniqlo importa; **Zara e Massimo Dutti falham.** Investigado a 2026-11-05: ambas respondem com um desafio anti-bot Akamai em vez do produto. Não se contorna; agora a app diz que a loja bloqueia. **No iPhone importam pelo [atalho](guias/09-atalho-importar-iphone.md)** (Safari → Partilhar → "Importar para o fio"). A 2026-11-05 o atalho leu os dados da Zara. Desde 2026-11-05 o atalho **manda logo para o fio** (com chave pessoal) e, por decisão do utilizador a 2026-11-06, a peça **entra sozinha no Armário** com valores por omissão (categoria pelo nome, cores da foto por confirmar); copiar e colar continua como alternativa. O fluxo completo falta confirmar no iPhone | Dizer que uma loja funciona |
| P-13 | Pinterest — **Decidido 2026-11-06: Partilhar → fio** (não a API) e, para a imagem, **perguntar sempre** | **Implementado:** o atalho do Safari manda o Pin (link, título, descrição) para o Perfil (inspirações). Lá escolhes "Só o link" ou "Com imagem". Desde 2026-11-10 a imagem vem com o envio: o Safari lê-a na página do Pin e o atalho manda-a (é preciso colar o script novo no atalho); sem ela, transferes tu e escolhes na galeria. O fio nunca lê o Pinterest, porque o robots.txt recusa leitores automáticos ([inspirações](features/inspiracoes-e-estilo.md#pinterest)). Falta confirmar no iPhone. A API oficial (quadros inteiros) fica para depois, se fizer falta | Importação automática de Pins |
| P-14 | Modelo IA — **POC aprovada pelo utilizador (2026-11-04)** ([IA local](features/ia-local.md#poc-implementada-2026-11-04)): runtime `flutter_onnxruntime`. Feitos os dois; desde 2026-11-06 descarregam-se sozinhos com a primeira peça com foto (remover em Definições › IA local desliga isso):
- recorte U²-Netp (Apache-2.0, 4,6 MB), usado nas cores pela foto; verificado só com imagens sintéticas;
- sugestão de categoria com Marqo FashionCLIP q4 (Apache-2.0, 80,9 MB): 90,2 % top-1 e 96,9 % top-3 em 621 fotos reais (CC0); verificado também na build Web no Chromium;
- peças parecidas com uma inspiração (o mesmo FashionCLIP): 74 % das 5 mais parecidas com a mesma etiqueta, nas mesmas fotos | Medir tempo e memória no Android e no iPhone, com fotos do guarda-roupa real | Ativar análise visual automática |
| P-15 | Assinatura/distribuição Android — **applicationId decidido 2026-11-03: `pt.rafaelfaria.guarda_roupa`** | Guardar chave de assinatura e comprovar atualização sem apagar dados | Distribuição estável |
| P-16 | Registo — **Decidido 2026-11-03: só o proprietário** (e uma conta de experiência) | Impor a regra no servidor (Auth + RLS), não apenas na UI | Expor login publicamente |
| P-20 | Manequim 3D dos conjuntos — **Adiado 2026-11-04** pelo utilizador ([feature](features/manequim-3d.md)) | Ao retomar: POC com moldes por categoria pintados com as cores das peças; decidir a origem dos modelos 3D | Nada no MVP |
| P-21 | Cores, padrões e texturas no conjunto — **Aceite pelo utilizador 2026-11-04** (proposta do mesmo dia): neutras = branco, cru, bege, caqui, castanho, cinzento, cinzento-escuro, preto, azul-marinho e ganga (fora da lista, croma OKLCH < 0,05); "tons próximos" = peças grandes com cor a menos de 30° de matiz; "um só destaque" = uma só peça com cor não neutra em ≥ 25 % da peça; dois padrões, ou duas texturas fortes (marcada, pelo), ficam a competir | **Implementado** ([motor](features/motor-de-combinacoes.md#conjunto-cores-padrões-e-texturas-2026-11-04)): as combinações só ordenam quando há uma preferência "Gosto"/"Evito" sobre elas; padrões/texturas a competir só desempatam e nunca excluem | Calibração do gosto |

## Ações do utilizador por fazer

Notas para não esquecer (2026-11-04):

1. ~~**Secret `SUPABASE_ACCESS_TOKEN`**~~ no GitHub (Settings → Secrets and variables → Actions), com um token criado no Supabase em Account → Access Tokens. **Feito a 2026-11-04:** o token precisa da permissão `edge_functions_write`. O workflow “Supabase” publica `import-product` a cada merge na `main`, e a função responde 401 sem sessão.
2. **Experimentar links reais** das lojas que se usam (P-12): na app (a função já está publicada) ou no Mac com o [smoke](../tool/import/README.md). Lojas importantes que falhem ou tragam dados errados: mandar o resultado para afinar o parser.
3. **Manequim 3D** (P-20): ideia guardada no roadmap; retomar mais tarde.
4. ~~**Rever a proposta P-21**~~ (cores, padrões e texturas). **Aceite a 2026-11-04.** Se, com o uso, a lista de neutras ou a regra dos padrões não bater com o teu gosto, diz o que mudar.
5. **IA local** (P-14, POC aprovada):
   - Experimentar, no Android e na PWA, o recorte, a sugestão de categoria e as peças parecidas de uma inspiração (Definições › IA local) com fotos tuas. A PWA precisa de `tool/models/fetch_models.sh` antes da build Web. Diz se as cores, as categorias e as peças parecidas acertam, e se o tempo de espera é aceitável no telemóvel.

   Detalhes em [IA local](features/ia-local.md#poc-implementada-2026-11-04).
6. ~~**Secret `POWERSYNC_ADMIN_TOKEN`**~~ no GitHub, uma vez só (2026-11-04). No PowerSync Dashboard, cria um token pessoal (Personal Access Token) e guarda-o com esse nome em Settings → Secrets and variables → Actions. Depois disso, o workflow “Supabase” faz sozinho o deploy de `powersync/sync-streams.yaml` a cada merge na `main`, e deixa de ser preciso colar as Sync Streams no painel. Sem o secret, o workflow avisa e não publica nada.
   - **Feito a 2026-11-04:** o secret existe e o deploy é automático. As permissões dos roles do PowerSync são dadas por `grant_powersync_select()` (migração `20261112000002`). O role da integração (`powersync_<id>`) não tinha SELECT em `plan_entries`, por isso o plano semanal não sincronizava entre dispositivos.
7. **Secrets do Cloudflare** para publicar a PWA (2026-11-04): `CLOUDFLARE_API_TOKEN` (Cloudflare Pages › Edit) e `CLOUDFLARE_ACCOUNT_ID`, pelos passos do [guia 04 §1](guias/04-publicar-pwa.md#1-uma-vez-só-a-conta-e-os-secrets-tu). Depois disso, cada merge na `main` publica em `https://guarda-roupa.pages.dev`. É o que permite testar tudo no iPhone (ações 2 e 5, P-05).

8. **Gemini (opcional, 2026-11-06):** criar uma chave grátis no Google AI Studio e guardá-la no GitHub como secret `GEMINI_API_KEY`, pelos [passos](features/ia-gemini.md#criar-a-chave-uma-vez-o-utilizador). Depois ligar em Definições › IA local e experimentar com algumas peças, uma etiqueta e o “Pedir ao stylist” em Hoje, e ver as “Peças que faziam falta” no Resumo do armário. Sem a chave, a app funciona como antes.

9. **Verificar no iPhone (2026-11-12):** fazer a [lista de 15 minutos](guias/10-verificar-no-iphone.md), que junta tudo o que está "por confirmar no iPhone". Se algo falhar, copiar o texto de Definições › Diagnóstico.
10. **Cores por omissão no motor (2026-11-11, por decidir):** hoje as combinações de cor só ordenam as sugestões quando há uma preferência guardada (P-21). Decidir se o motor passa a puxar para cima, sem preferências, neutras com um só destaque e tons próximos.

Também em aberto: a POC em dois dispositivos (P-03). Com só um iPhone, o segundo dispositivo pode ser o Chrome no Mac, com a mesma conta.

## O que já não está pendente como requisito

Sync desde o início; sync em primeiro plano suficiente; apenas uso confirmado; replaneamento com confirmação; inspirações assistidas primeiro; t-shirt como top único possível; repetição de calçado/acessórios para este utilizador.

## POC mínima de sincronização

1. Criar conta de experiência isolada.
2. Adicionar peça/foto no Android e observar na PWA.
3. Editar offline e reconectar sem perder a alteração.
4. Confirmar a mesma entrada nos dois dispositivos sem duplicar o evento.
5. Produzir um conflito de disponibilidade e observar a resolução definida.
6. Eliminar/arquivar, reconectar um dispositivo antigo e impedir recuperação involuntária.
7. Interromper upload de imagem e retomar com estado honesto.
8. Comprovar isolamento com outra conta.

Idempotência de retries e da mesma entrada de plano não deduplica magicamente duas utilizações manuais independentes.

## Riscos que permanecem mesmo com boa implementação

- Offline não conhece alterações recentes de outro dispositivo.
- Previsões mudam; uma recomendação não controla o tempo real.
- Aparência e conforto são subjetivos.
- Browser/OS podem remover dados locais.
- Free tiers podem alterar limites ou suspender por inatividade.
- Lojas e plataformas podem mudar acessos.

## Registo de decisões

| ID | Decisão | Responsável | Data | Estado |
|---|---|---|---|---|
| P-01 | Supabase Free como backend (Auth, PostgreSQL com RLS, Storage privado) | Utilizador | 2026-11-03 | Feito: projeto criado e em uso |
| P-02 | Google OAuth como único método de login inicial | Utilizador | 2026-11-03 | Feito: configurado e em uso |
| P-03 | PowerSync + Supabase como motor de sincronização | Utilizador | 2026-11-03 | Aprovado provisoriamente: ligado e sincronizado; testes com dois dispositivos adiados pelo utilizador (problemas tratados quando aparecerem) |
| P-16 | Apenas o proprietário (e conta de experiência) pode usar a app | Utilizador | 2026-11-03 | Implementado no servidor: `allowed_users`, `is_allowed()` nas políticas e funções, hook “Before User Created” |
| P-20 | Manequim 3D dos conjuntos fica para mais tarde, no roadmap | Utilizador | 2026-11-04 | Adiado |
| P-12 | Qualquer site público, aprendido por domínio (substitui a lista Zara, Uniqlo, Pull&Bear e Bershka); Supabase Edge Functions | Utilizador | 2026-11-04 | Decidido; estado de cada site vem do uso |
| P-15 | `applicationId` = `pt.rafaelfaria.guarda_roupa` (fixo a partir do OAuth/primeira instalação) | Utilizador | 2026-11-03 | Decidido; assinatura release por definir |
| P-17 | Limites de conforto (proposta: 22/14 °C, vento 30 km/h) | Utilizador | 2026-11-03 | Decidido; editável nas Definições (2026-11-04) |
| P-18 | Localização Torres Vedras, Europe/Lisbon, sem GPS | Utilizador | 2026-11-03 | Decidido |
| P-19 | 7 dias; úteis em trabalho (smart casual), fim de semana a decidir e provisório | Utilizador | 2026-11-04 | Decidido |
| P-11 | Recuperar um backup numa conta com dados: juntar (acrescentar o que falta; o que está fica; apagadas só se marcadas) | Utilizador | 2026-11-06 | Implementado |
| P-07b | Lavandaria sozinha: ao chegar ao limiar a peça vai para “Precisa de limpeza”; volta só com “Lavei hoje” ou à mão | Utilizador | 2026-11-06 | Implementado |
| P-14b | Modelos de IA descarregados sozinhos com a primeira peça com foto; remover desliga | Utilizador | 2026-11-06 | Implementado |
| P-19b | Semana sozinha: dias por planear enchem-se já aceites; trocas aplicam-se sozinhas com aviso e “Desfazer”. Uso nunca se regista sozinho (P-08) | Utilizador | 2026-11-06 | Implementado |
| P-22 | Nome **fio**, logótipo "f" de fio e visual v2 (diário pessoal, não loja) | Utilizador | 2026-11-05 | Aplicado: tema, nome, ícone e ecrãs Hoje, Armário e Peça ([design](design-e-fluxos.md)). Outros ecrãs herdam o tema |
| P-04 | ADR-008: ordem conservadora de disponibilidade, edições de plano concorrentes como proposta, logout com pendências bloqueado | Utilizador | 2026-11-03 | Decidido; validação na POC |

## Registo futuro de fecho

Para cada ID: decisão, responsável, data, versões, procedimento, resultado observado e limitações. Se falhar, documentar alternativa e impacto no roadmap, não improvisar um fallback pago ou silencioso.
