# Guia 06 — Executar validações de comportamento

Quando: em cada incremento, com a feature e o respetivo teste já implementados. Responsável pela automação e diagnóstico: quem implementa. Tu disponibilizas dispositivos e executas/acompanhas os percursos físicos que não estiverem automatizados.

**Os comandos e percursos abaixo são futuros. Não existem suites da aplicação neste dossier e nenhum cenário está aprovado por esta exportação.**

Referências: [guidelines de testes](../guidelines/testes.md), [matriz E2E](../plano-e2e.md) e P-09/P-10 de [Pendências](../pendencias.md).

## 1. Preparação obrigatória

1. Abrir o repositório real, por exemplo `$HOME/Developer/wardrobe_app`, não esta pasta de documentação.
2. Confirmar a revisão, versões Flutter/Dart, runner, OS e browser.
3. Usar contas e dados descartáveis, nunca limpar o guarda-roupa pessoal para preparar um teste.
4. Confirmar qual o backend de experiência e quais as chamadas reais. Não colocar secret keys no cliente de testes.
5. Preparar relógio, seed e fixtures quando o cenário exigir repetibilidade; registar esses controlos.
6. Confirmar que UI, motor, repositórios, base de dados e media são as implementações reais no percurso E2E.
7. Se o teste exigir P-03/P-04 ainda por fechar, marcar **bloqueado**, não inventar o resultado esperado.

Os caminhos de testes dos exemplos são propostos: só executar depois de os ficheiros existirem e corresponderem ao cenário. O responsável adapta os comandos aos nomes reais e fixa versões compatíveis. Não instalar packages só por ler este guia.

## 2. Verificações focadas

Na futura raiz Flutter:

```bash
flutter --version
flutter devices
flutter analyze
```

Para formatação, usar apenas diretórios existentes; exemplo para um projeto com `lib` e `test`:

```bash
dart format --output=none --set-exit-if-changed lib test
```

Se o trabalho for na lavandaria e existir essa pasta de testes:

```bash
flutter test test/features/laundry
```

Usar o seletor real mais pequeno que cubra a alteração. Alargar a suite quando houver impacto transversal, migração ou falha não localizada.

Análise estática e testes de domínio não demonstram por si só foto persistente, sincronização ou funcionamento no iPhone.

## 3. E2E automatizado — Android e Chromium

Pré-requisitos: Patrol configurado no projeto, CLI compatível, permissões/dados de teste preparados e POC P-10 executada. Se faltar tooling, seguir o setup da versão aprovada, não adicionar dependências incompatíveis ao acaso.

1. Confirmar ferramentas e opções:

```bash
patrol --version
patrol test --help
flutter devices
```

2. Substituir o ID Android e o caminho pelo teste real. Exemplo:

```bash
patrol test --device ID_ANDROID \
  --target patrol_test/wardrobe_journey_test.dart
```

3. Para Chromium, a documentação primária confirma este formato:

```bash
patrol test --device chrome \
  --target patrol_test/wardrobe_journey_test.dart
```

4. Quando adequado, a opção documentada para execução Web sem janela é:

```bash
patrol test --device chrome \
  --target patrol_test/wardrobe_journey_test.dart \
  --web-headless
```

5. Usar a configuração de teste isolada suportada pelo projeto. Estes exemplos não configuram automaticamente o backend nem criam `wardrobe_journey_test.dart`.
6. Guardar resultado e primeira falha antes de qualquer nova tentativa.

Não há neste plano um comando Safari/`--device ios` que prove a PWA de iPhone. Também não usar `--device android` em vez do ID efetivo. A validação iPhone abaixo continua necessária.

## 4. Percurso manual — foto, persistência e offline

Executar no Android e numa PWA realmente instalada no iPhone. Os nomes de ecrãs/ações são propostas de UX, não controlos já implementados.

1. Com rede, entrar na conta de experiência.
2. Em **Guarda-roupa > Adicionar peça**, criar uma t-shirt usando uma fotografia real do seletor/câmara suportada.
3. Orientar/recortar, preencher atributos e guardar.
4. Abrir a peça e confirmar texto, imagem e estado de upload.
5. Fechar completamente a app pelo gestor de aplicações e reabrir. Confirmar que não se depende apenas da memória do processo.
6. No iPhone, repetir com os formatos realmente produzidos pelo aparelho, incluindo HEIC quando disponível. Registar qualquer limitação.
7. Esperar pela preparação offline e pela disponibilidade local das fotos necessárias.
8. Desligar efetivamente as ligações: modo de voo e Wi-Fi/dados móveis desligados, incluindo qualquer Wi-Fi que permaneça ativo.
9. Confirmar que um recurso de rede não armazenado deixa de estar acessível; no ambiente automatizado pode usar-se um endpoint de controlo sem cache.
10. Fechar e reabrir pelo ícone da app/PWA, não apenas voltar ao separador ainda aberto.
11. Confirmar catálogo e foto local. Editar um atributo e observar a indicação de pendência.
12. Reabrir novamente ainda sem rede e verificar a edição.
13. Restabelecer a rede, manter a app aberta e observar o envio e a chegada ao outro dispositivo.

Esperado: dados e fotos persistentes, indicação honesta de offline e convergência posterior. Uma signed URL ainda em cache não substitui persistência local comprovada.

Repetir cancelamento do picker e recusa de permissão. Nenhum deve produzir sucesso fictício ou perda da edição anterior.

## 5. Percurso manual — outfits, uso e lavandaria

1. Preparar na conta de experiência uma t-shirt, uma parte de baixo e calçado disponíveis, com contexto/ocasião compatíveis.
2. Gerar um conjunto pela UI com o motor real. Num contexto ameno adequado, aceitar t-shirt como único top, sem casaco obrigatório.
3. Verificar que nenhum item aparece duas vezes e que as peças pertencem ao utilizador.
4. Guardar e classificar por ocasião. Gerar/guardar um plano sem confirmar utilização.
5. Confirmar que planeamento/reservas não incrementam contagens reais.
6. Para o teste, configurar uma política ilustrativa de aviso ao segundo uso. Isto não aprova esse valor como default do produto.
7. Registar duas utilizações de experiência distintas, pelos fluxos permitidos. Não tentar obter dois usos repetindo a confirmação da mesma entrada.
8. Verificar o aviso no limiar e confirmar que a peça continua disponível.
9. Marcar explicitamente a peça como suja. Uma nova geração deve excluí-la; se faltar alternativa, explicar a limitação em vez de a reutilizar.
10. Confirmar limpeza e verificar reset da contagem relevante. Enquanto estiver a secar, continuar a excluir.
11. Marcar pronta e voltar a permitir a peça.
12. Fechar/reabrir e comprovar os estados.

Num segundo cenário apropriado ao frio, testar a t-shirt como camada inferior, sem duplicar o mesmo item em outro papel.

Ao alterar meteorologia/disponibilidade de um plano aceite, verificar aviso e proposta. Sem confirmação, o plano não deve ser reescrito silenciosamente.

## 6. Percurso manual — dois dispositivos e conflitos

Usar Android e PWA instalada com a mesma conta de experiência:

1. Sincronizar uma entrada de plano ainda não confirmada em ambos.
2. Desligar efetivamente a rede nos dois.
3. Confirmar essa mesma entrada em cada um e fechar/reabrir.
4. Reconectar ambos, abrir a aplicação e aguardar estado convergente observável.
5. Verificar que existe um uso lógico, não dois. Duas entradas manuais independentes são um problema diferente, não uma deduplicação garantida.
6. Preparar uma peça comum; editar offline num aparelho e produzir uma alteração concorrente no outro.
7. Reconectar e observar a resolução aprovada em P-04. Se ainda não existe semântica aprovada, o cenário está bloqueado.
8. Num conflito de suja/disponível, não aceitar uma regressão silenciosa para limpa.
9. Arquivar/eliminar no primeiro aparelho e reconectar uma cópia antiga no segundo. Não ressuscitar involuntariamente a peça.
10. Interromper upload de foto e retomar. Metadata sincronizada não significa imagem já enviada.

Testar também conta A/conta B com dados descartáveis: a segunda não pode obter linhas ou media privadas da primeira. Logout/troca de conta não deve apagar pendências sem decisão nem misturar caches.

## 7. Outros gates

| Área | Como executar |
|---|---|
| Backup completo e recuperação | Seguir [Guia 07](07-operacao-backups-e-limites.md), num destino isolado |
| Atualização Android | APK da mesma identidade, dados antigos e migração; [Guia 05](05-instalar-android-e-pwa.md) |
| Meteorologia controlada | Fixture identificada de calor/frio/chuva, restante fluxo real |
| Serviço real | Smoke separado e limitado, sem substituir o teste controlado nem reclamar suporte universal |
| Desempenho | Inventários 10/50/100 e maiores quando necessário; aparelhos e budgets definidos em P-09 |
| Acessibilidade e datas | Texto ampliado, teclado/semântica, Europe/Lisbon e transições de hora |

Não transformar um timeout do motor em prova de impossibilidade matemática. Não impor um teto de 100 peças por ser um dos cenários de medição.

## 8. Registar a evidência

Usar este modelo num registo de execução do futuro projeto:

```text
Cenário/ID:
Data e revisão da app:
Aparelho, OS, browser/PWA e versões:
Versões do runner e backend:
Conta/dados de experiência:
Relógio, seed e fronteiras controladas:
Pré-condições e passos:
Resultado esperado:
Resultado observado:
Estado: não executado | bloqueado | falhou | passou
Evidência redigida:
Limitações e limpeza segura dos dados de experiência:
```

Remover tokens, signed URLs, emails e fotografias pessoais de logs partilháveis. Esperar por condições observáveis com timeout; não acrescentar sleeps ou retries para esconder flakes.

Só marcar “passou” com observação real na plataforma indicada. Verificar os Markdown desta entrega não executa qualquer um destes testes da aplicação.
