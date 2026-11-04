# Pendências, riscos e provas de viabilidade

Data: 2026-10-31. Nenhuma POC da aplicação foi executada durante a criação deste dossier.

Uma pendência não deve desaparecer por estar descrita em Markdown. Fechar apenas com decisão/evidência e data.

| ID | Tema e estado | Como fechar | Bloqueia |
|---|---|---|---|
| P-01 | Backend — **Decidido 2026-11-03: Supabase Free** | Criar projeto (guia 02) e registar região/limites | Criação da infraestrutura |
| P-02 | Login — **Decidido 2026-11-03: Google OAuth** | Configurar projeto Google e callbacks (guia 03); demonstrar entrada e recuperação | Fluxo de conta |
| P-03 | Sync — **Aprovado provisoriamente 2026-11-03: PowerSync + Supabase** (ligação e autenticação a funcionar; testes com dois perfis/dispositivos do [guia 08 §7](guias/08-poc-sincronizacao.md) por fazer) | Executar os testes do §7; se falharem, corrigir ou recorrer ao protocolo próprio | Uso real em dois dispositivos |
| P-04 | Conflitos e privacidade — **Decidido 2026-11-03: [ADR-008](decisoes/008-conflitos-e-privacidade.md)** | Validar na POC (passos 4–8) e E2E-04/11/14 | Uso da conta em dois dispositivos |
| P-05 | PWA/fotografias — **Implementado 2026-11-03 sem validação em aparelho** (JPEG/PNG/WebP; HEIC dá erro claro) | Demonstrar armazenamento persistente, quotas, HEIC e reabertura offline no iPhone | Onboarding real |
| P-06 | Rotatividade — **Decidido 2026-11-03:** mínimo de 3 dias entre usos para tops, 2 para partes de baixo (calças, saias, calções), sem intervalo para casacos, calçado e acessórios; preferir as menos usadas; editável por categoria e por peça; sem alternativa, sugerir na mesma com aviso claro (não é modo estrito) | **Implementado** (`RotationPolicy`, valores por categoria/peça); falta ligar ao motor de combinações | Motor com políticas reais |
| P-07 | Lavagem — **Decidido 2026-11-03:** referência USU/ACI, só informativa e editável: t-shirts, tops e roupa desportiva após cada uso; camisas e polos 2 usos; camisolas, calças, ganga, saias e vestidos 4 usos; casacos e calçado sem aviso. Nunca muda a disponibilidade sozinha | **Implementado** (`LaundryPolicy`, limpezas, avisos e valores por categoria/peça) | Avisos iniciais |
| P-08 | Rotina — **Decidido 2026-11-03 (confirmação):** botão “Vesti hoje” no ecrã de hoje, escolher as peças (ou confirmar o plano) e guardar; corrigir e desfazer depois; sem notificações por agora; planear nunca conta como uso. **Implementado** (registo, histórico, corrigir, desfazer). Dias/ocasiões por defeito do planeamento semanal por decidir | Decidir a rotina semanal com o planeador (incrementos 5–6) | MVP de utilização |
| P-17 | Conforto — **Decidido 2026-11-03 (proposta):** sensação térmica ≥ 22 °C peças leves; 14–22 °C peças médias (ou leves) com camada opcional; < 14 °C peças quentes, ou leve/média mais casaco; chuva ou vento ≥ 30 km/h preferem casaco e calçado marcados para chuva/vento. Editável mais tarde | **Implementado** no motor (`ComfortThresholds`, `ComfortRules`) e editável em Definições › Conforto e tempo, por dispositivo e sem sincronizar ([meteorologia](features/meteorologia.md)). Falta calibrar o que conta como "chuva" na previsão | Calibração pessoal |
| P-18 | Localização — **Decidido 2026-11-03:** Torres Vedras, coordenadas aproximadas da cidade, fuso Europe/Lisbon, editável nas Definições; Open-Meteo sem GPS | **Implementado** (localização nas Definições, previsão com cache); usada em "Sugestões para hoje" | Previsão real |
| P-19 | Semana e ocasiões — **Decidido 2026-11-04:** planear os 7 dias; dias úteis começam em “Trabalho (smart casual)” (o trabalho não pede roupa formal); sábado e domingo ficam “a decidir” (sem ocasião) e provisórios: pode não acontecer nada que peça essa roupa, e o dia pode ficar vazio. Um plano nunca conta como utilização (P-08) | **Dados implementados** (`plan_entries`, `apply_plan_operation`, regras `WeekPlanRules`); pesquisa semanal (`WeeklyPlanner`), ecrã “Esta semana” e mudanças posteriores (`PlanReview`) feitos | Semana utilizável |
| P-09 | Perfis e desempenho | Escolher dispositivos de referência e orçamento mensurável | Gate de desempenho |
| P-10 | Automação E2E | POC Patrol Android/Chromium; guião iPhone real, sem equivalência fictícia | Evidência por plataforma |
| P-11 | Recuperação com cloud | Definir substituição/recuperação sem replay de eventos nem ressurreição silenciosa | Recuperação sobre conta existente |
| P-12 | Lojas suportadas — **Decidido 2026-11-04:** qualquer site público, com perfil por domínio que se atualiza sozinho (antes: Zara, Uniqlo, Pull&Bear e Bershka); função em Supabase Edge Functions | **Função e fluxo na app feitos**; falta publicar a função (secret `SUPABASE_ACCESS_TOKEN`) e o [smoke](../tool/import/README.md) com links reais (corre no Mac; a cloud não chega às lojas) | Dizer que uma loja funciona |
| P-13 | Pinterest | Confirmar permissões/API; link não garante imagem | Importação automática de Pins |
| P-14 | Modelo IA | Licença, operadores, tamanho, precisão e desempenho | Ativar análise visual automática |
| P-15 | Assinatura/distribuição Android — **applicationId decidido 2026-11-03: `pt.rafaelfaria.guarda_roupa`** | Guardar chave de assinatura e comprovar atualização sem apagar dados | Distribuição estável |
| P-16 | Registo — **Decidido 2026-11-03: só o proprietário** (e uma conta de experiência) | Impor a regra no servidor (Auth + RLS), não apenas na UI | Expor login publicamente |
| P-20 | Manequim 3D dos conjuntos — **Adiado 2026-11-04** pelo utilizador ([feature](features/manequim-3d.md)) | Ao retomar: POC com moldes por categoria pintados com as cores das peças; decidir a origem dos modelos 3D | Nada no MVP |
| P-21 | Cores, padrões e texturas no conjunto — **Proposta 2026-11-04, por rever pelo utilizador:** neutras = branco, cru, bege, caqui, castanho, cinzento, carvão, preto, azul-marinho e ganga (fora da lista, croma OKLCH < 0,05); "tons próximos" = peças grandes com cor a menos de 30° de matiz; "um só destaque" = uma só peça com cor não neutra em ≥ 25 % da peça; dois padrões, ou duas texturas fortes (marcada, pelo), ficam a competir | **Implementado como proposta** ([motor](features/motor-de-combinacoes.md#conjunto-cores-padrões-e-texturas-2026-11-04)): as combinações só ordenam quando há uma preferência "Gosto"/"Evito" sobre elas; padrões/texturas a competir só desempatam e nunca excluem | Calibração do gosto |

## Ações do utilizador por fazer

Notas para não esquecer (2026-11-04):

1. **Secret `SUPABASE_ACCESS_TOKEN`** no GitHub (Settings → Secrets and variables → Actions), com um token criado no Supabase em Account → Access Tokens. Depois correr à mão o workflow “Supabase” (ou esperar pelo próximo merge na `main`). Sem ele a função `import-product` não é publicada e a app diz “A importação não está disponível agora”.
2. **Experimentar links reais** das lojas que se usam (P-12): na app, depois de publicar a função, ou no Mac com o [smoke](../tool/import/README.md). Lojas importantes que falhem ou tragam dados errados: mandar o resultado para afinar o parser.
3. **Manequim 3D** (P-20): ideia guardada no roadmap; retomar mais tarde.
4. **Rever a proposta P-21** (cores, padrões e texturas): se a lista de neutras ou a regra dos padrões não bate com o teu gosto, diz o que mudar. Para já só pesa quando há uma preferência de combinação em Estilo › Preferências.

Também em aberto: voltar a fazer deploy das Sync Streams no PowerSync quando um stream novo é adicionado; a POC em dois dispositivos (P-03).

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
| P-01 | Supabase Free como backend (Auth, PostgreSQL com RLS, Storage privado) | Utilizador | 2026-11-03 | Decidido; projeto ainda não criado |
| P-02 | Google OAuth como único método de login inicial | Utilizador | 2026-11-03 | Decidido; não configurado |
| P-03 | PowerSync + Supabase como motor de sincronização | Utilizador | 2026-11-03 | Aprovado provisoriamente: ligado e sincronizado; testes com dois dispositivos adiados pelo utilizador (problemas tratados quando aparecerem) |
| P-16 | Apenas o proprietário (e conta de experiência) pode usar a app | Utilizador | 2026-11-03 | Implementado no servidor: `allowed_users`, `is_allowed()` nas políticas e funções, hook “Before User Created” |
| P-20 | Manequim 3D dos conjuntos fica para mais tarde, no roadmap | Utilizador | 2026-11-04 | Adiado |
| P-12 | Qualquer site público, aprendido por domínio (substitui a lista Zara, Uniqlo, Pull&Bear e Bershka); Supabase Edge Functions | Utilizador | 2026-11-04 | Decidido; estado de cada site vem do uso |
| P-15 | `applicationId` = `pt.rafaelfaria.guarda_roupa` (fixo a partir do OAuth/primeira instalação) | Utilizador | 2026-11-03 | Decidido; assinatura release por definir |
| P-17 | Limites de conforto (proposta: 22/14 °C, vento 30 km/h) | Utilizador | 2026-11-03 | Decidido; editável nas Definições (2026-11-04) |
| P-18 | Localização Torres Vedras, Europe/Lisbon, sem GPS | Utilizador | 2026-11-03 | Decidido |
| P-19 | 7 dias; úteis em trabalho (smart casual), fim de semana a decidir e provisório | Utilizador | 2026-11-04 | Decidido |
| P-04 | ADR-008: ordem conservadora de disponibilidade, edições de plano concorrentes como proposta, logout com pendências bloqueado | Utilizador | 2026-11-03 | Decidido; validação na POC |

## Registo futuro de fecho

Para cada ID: decisão, responsável, data, versões, procedimento, resultado observado e limitações. Se falhar, documentar alternativa e impacto no roadmap, não improvisar um fallback pago ou silencioso.
