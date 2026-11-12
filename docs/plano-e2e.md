# Plano de validação E2E

Estado em 2026-10-31: **cenários planeados; nenhum teste da aplicação executado**. Desde 2026-11-12 há uma [lista curta para o iPhone](guias/10-verificar-no-iphone.md), que cobre o essencial de E2E-01, 02, 07, 08, 11, 12, 13 e 15 na PWA instalada; os resultados registam-se aqui quando o utilizador a fizer.

Plataformas: A = Android, C = Chromium/Web, I = PWA instalada num iPhone real. “Previsto” indica âmbito, não resultado aprovado.

## Matriz de cenários

| ID | Percurso e resultado esperado | Plataformas previstas |
|---|---|---|
| E2E-01 | Criar/editar/arquivar peça pela UI, fechar e reabrir; dados preservados e duas unidades iguais independentes | A, C, I |
| E2E-02 | Selecionar foto real, orientar/recortar, guardar e reabrir offline; testar formatos de iPhone, cancelamento e permissão recusada | A, C, I |
| E2E-03 | Guardar conjunto t-shirt + calças + ténis sem casaco, classificar por ocasiões e editar sem reescrever histórico | A, C, I |
| E2E-04 | Confirmar uso em um toque; retry e confirmação da mesma entrada em dois dispositivos geram um uso lógico; corrigir coerentemente | A + I; C como complemento |
| E2E-05 | Gerar com intervalos, alternativas escassas e sapatos repetíveis; exceções explícitas e nenhuma violação de disponibilidade | A, C, I |
| E2E-06 | Limiar de lavagem apenas avisa; marcar suja/em lavagem/a secar exclui; pronta volta a permitir; sem limpeza futura presumida | A, C, I |
| E2E-07 | Previsão fria/quente/chuva, cache antiga e ausência de rede; mudar previsão apenas propõe alteração | A, C, I |
| E2E-08 | Gerar pela UI com motor real; papéis completos, só posse, sem duplicação e com razões/unknowns/limites corretos | A, C, I |
| E2E-09 | Planear semana com escolhas fixadas e reservas; não incrementar uso; alterações só após aceitação | A, C, I |
| E2E-10 | Adicionar inspiração/URL e etiquetas; preferências afetam scoring sem criar peças nem interpretar imagem inacessível | A, C, I |
| E2E-11 | Dois dispositivos: create/edit offline, reconnect, conflito, delete antigo, sessão expirada e media interrompida | A + I; C adicional |
| E2E-12 | Link suportado e variante, link sem metadata, erro/timeout e domínio não suportado; formulário manual preserva origem | A, C, I, após importador |
| E2E-13 | Exportar dados+imagens, verificar ficheiro e recuperar num destino autorizado; rejeitar corrupção/versão sem alterações parciais | A, C, I |
| E2E-14 | Conta B não acede a linhas/media de A; logout não perde pendências sem decisão nem mistura caches | A, C, I |
| E2E-15 | Instalar PWA, primeira carga online, reabrir offline, atualizar app e tratar quota/persistência sem apagar dados | C, I; I obrigatório |
| E2E-16 | Atualizar APK com mesma assinatura, preservar base/fotos e executar migração com dados antigos | A |
| E2E-17 | Europe/Lisbon, mudança de hora, datas locais, texto ampliado, teclado e semântica/contraste de estados | A, C, I |
| E2E-18 | Inventários 10/50/100 e maiores quando necessário; medir pesquisa/listas/memória sem cap artificial nem ótimo fictício | A, C, I |
| E2E-19 | Modelo opcional: download/inferência/correção/recusa; formulário continua funcional sem modelo | Futuro, A/C/I |
| E2E-20 | Compra/cancelamento/expiração/webhook repetido e entitlement validado | Futuro, conforme canal |

## Percurso crítico de sync — detalhe

1. Entrar na mesma conta de experiência nos dois aparelhos.
2. Criar uma peça/foto no Android e observar a chegada na PWA.
3. Desligar a rede do Android e editar; fechar e reabrir antes de reconectar.
4. Editar o mesmo atributo/estado na PWA para criar concorrência.
5. Reconectar e observar pendências, convergência ou conflito documentado.
6. Confirmar uma mesma entrada em ambos offline e sincronizar; obter um uso lógico.
7. Eliminar/arquivar uma peça num aparelho; reconectar uma cópia antiga sem ressurreição silenciosa.
8. Interromper e retomar upload; nunca mostrar media completamente sincronizada antes do fim.

Executar apenas com dados isolados. Testar operações reais do servidor, não só endpoints simulados.

## Dados de teste

Inventários autorizados/sintéticos que incluam: tops simples, peça única, várias texturas/padrões, calçado escasso, peça suja, atributos desconhecidos, duas unidades iguais e referência de estilo não possuída.

As fixtures de meteorologia permitem cenários repetíveis. Um smoke separado confirma o serviço real e atribuição.

## Desempenho

P-09 deve fixar aparelho/OS/browser, modo profile/release, quantidade de dados, cache quente/fria e budgets numéricos antes de exigir um “passou”.

Medir p50/p95 de geração diária/semanal, candidatos/estados expandidos, memória de processamento de foto e latência observável de catálogo/sync. Separar tempo de rede de CPU.

Não concluir que “escala” apenas por ter 100 linhas ou uma arquitetura por camadas.

## Registo de execução futuro

Por cenário: versão/commit, data, aparelho/OS/browser, dados, dependências reais/controladas, passos, esperado, observado, resultado e evidência redigida.

Resultados permitidos: passou, falhou, bloqueado ou não executado. Nesta entrega todos permanecem **não executados**.

As verificações de integridade dos próprios Markdown não são resultados E2E da aplicação.
