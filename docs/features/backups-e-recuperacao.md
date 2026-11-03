# Feature — Backups e recuperação

Estado: necessária na base utilizável; recuperação sobre conta sincronizada existente exige protocolo aprovado.

Implementado (2026-11-03): exportação e verificação do formato v4 (lê também v1, v2 e v3).

- **Conteúdo:** `manifest.json` (formato, versão, `exported_at`, contagens, `pending_operations` e a lista de ficheiros com caminho, MIME, tamanho e SHA-256), `data/garments.json` com as colunas do servidor, sem `owner_id`, `data/history.json` (desde a v2), `data/outfits.json` (desde a v3), `data/style.json` (desde a v4) e `photos/{id}/main.jpg|thumb.jpg`.
- **Histórico (v2):** utilizações (“Vesti hoje”) e limpezas ativas — as desfeitas ficam de fora — e os valores de lavagem/rotatividade escolhidos por categoria e por peça. Só entra o que refere peças exportadas: uma utilização com uma peça entretanto eliminada fica só com as restantes. O plano (`plan_entry_id`) não entra. Um backup v1 continua a ser lido (sem histórico); um v2 sem `data/history.json`, ou com histórico que refira peças que não estão no ficheiro, datas inválidas ou valores fora dos limites, é rejeitado por inteiro.
- **Conjuntos (v3):** os conjuntos guardados ativos, com nome, ocasiões e peças/papéis. Peças eliminadas saem do conjunto; um conjunto que fique sem peças fica de fora. Peças arquivadas mantêm-se. Na recuperação, os conjuntos ganham ids novos e apontam para as peças novas (`create_outfit`). Um v2 continua a ser lido (sem conjuntos); um v3 sem `data/outfits.json`, ou com um conjunto inválido (as mesmas regras do servidor) ou que refira peças que não estão no ficheiro, é rejeitado por inteiro.
- **Estilo (v4):** as inspirações e as preferências de estilo ativas. Uma preferência cuja inspiração já foi eliminada vai sem origem. Na recuperação ganham ids novos e a origem aponta para a inspiração nova (`create_inspiration`, `create_preference`). Como o destino só tem de estar sem peças, pode já ter estilo: uma inspiração igual reutiliza-se e uma preferência com o mesmo assunto, valor e contexto não se repete (fica a do destino). Um v3 continua a ser lido (sem estilo); um v4 sem `data/style.json`, ou com uma inspiração ou preferência inválida (as mesmas regras do servidor) ou com uma origem que não está no ficheiro, é rejeitado por inteiro.
- **Snapshot:** é lido numa transação de leitura. As peças eliminadas ficam de fora.
- **Fotografias:** as que faltam neste dispositivo são descarregadas e verificadas pelo hash. Se faltar alguma, a exportação falha.
- **Verificação antes de gravar:** o ZIP é relido pelo mesmo leitor que a recuperação vai usar.
- **O leitor rejeita o ficheiro inteiro** quando:
  - não é um ZIP desta app;
  - é de uma versão mais recente;
  - tem caminhos fora das pastas esperadas (`..`), ficheiros não declarados, tamanhos ou hashes errados, ou fotos em falta;
  - tem peças inválidas;
  - excede os limites de número e tamanho de ficheiros.
- **Gravação:** usa o "Guardar como" do sistema (`file_saver`), que no Android grava fora da pasta privada (SAF). Na Web, a mensagem diz que a transferência começou, não que o ficheiro ficou guardado.
- **Memória:** o ZIP é construído todo em memória, o que é suficiente para algumas centenas de peças com até 5 fotos cada.

Recuperação (primeiro modo, só para destino vazio):

- **Percurso:** Definições › Recuperar backup › escolher o ZIP (`file_selector`).
- **Antes de mostrar o preview, valida o ficheiro** com o leitor acima.
- **Valida também o destino:**
  - a conta não pode ter peças;
  - com cloud, a primeira sincronização tem de ter terminado, porque antes disso não se sabe se a conta está vazia.
- **Preview:** data, contagens de peças, fotografias, histórico, conjuntos e estilo, e as alterações que ainda não estavam sincronizadas na exportação.
- **Aplicação:**
  - acontece só depois de confirmar e corre numa única transação;
  - o destino é verificado de novo dentro da transação; se entretanto deixou de estar vazio, nada é escrito.
  - o histórico é recriado na mesma transação com os ids novos das peças, pela ordem original de registo (o servidor mantém a ordem entre uma utilização e uma limpeza do mesmo dia), e segue pela fila normal depois das peças. Como só há recuperação para destino vazio, não duplica utilizações de uma conta existente.
- **IDs novos para peças e fotografias:** nada ressuscita uma peça eliminada nem colide com IDs que o servidor já conhece, mesmo quando o backup é desta mesma conta.
  - Mantém a data de criação original.
  - O estado (disponibilidade, arquivo) e as fotografias entram como operações normais: `create`, `set_availability`, `attach_photo`, `archive`. A fila envia os ficheiros antes de ligar as fotos.

Bloqueado até P-11: recuperar por cima de uma conta com dados (juntar ou substituir).

## Objetivo

Permitir recuperar dados e fotografias sem depender de um browser, dispositivo ou free tier específico.

**Sincronização não é backup:** uma eliminação ou erro pode propagar-se. Um ficheiro com o inventário mas sem imagens não é um backup completo do produto.

## Formato recomendado

ZIP com manifest e JSON versionados, dados de domínio e ficheiros referenciados. Incluir:

- Versão do formato/schema e data da exportação.
- Identidades/relações, planos, utilizações e eventos de cuidado.
- Políticas e preferências.
- Assets com caminho relativo, MIME, tamanho e hash.
- Estado da exportação e informação sobre alterações ainda não sincronizadas.

Não exportar tokens, passwords, chaves secretas ou signed URLs como única referência a fotografias.

SHA-256 verifica integridade, não confidencialidade. Um ZIP comum não está encriptado; recomendar uma localização privada e protegida do utilizador.

## Exportação

1. Ler um snapshot consistente, identificando o ponto de corte.
2. Reunir os assets referenciados.
3. Verificar que nenhum está em falta.
4. Gerar manifest/hashes e ficheiro.
5. Efetuar download/guardar fora da app e confirmar conclusão observável.

Ficheiro apenas na pasta privada Android não é um backup externo. Na Web, iniciar download não prova que o utilizador guardou o ficheiro.

## Recuperação proposta

1. Selecionar ficheiro e validar versão, limites, caminhos e hashes.
2. Preparar dados numa área isolada.
3. Mostrar preview, conteúdo e impacto.
4. Só aplicar num destino permitido pelo modo de recuperação aprovado.
5. Confirmar catálogo, imagens, planos e histórico depois de reabrir.
6. Retomar sync apenas com semântica definida.

No primeiro modo, recomendar destino vazio e autenticado. Recuperar por cima de uma conta com dados não é “apagar a base local e voltar a sincronizar”.

Até P-11 estar fechada, bloquear merge/substituição cloud existente. Não propagar eventos antigos como novas utilizações, restaurar tokens ou ressuscitar deletes em segredo.

## Tecnologia e alternativas

`archive` para ZIP, `file_selector` para importação e `file_saver`/adaptação de plataforma para exportação. Verificar limites de memória para bibliotecas que constroem todo o ZIP em RAM.

| Opção | Avaliação |
|---|---|
| JSON versionado + assets | Recomendado: portável e auditável |
| Copiar só SQLite | Pode ajudar diagnóstico, mas é dependente do schema e não inclui automaticamente imagens |
| Só CSV | Bom para leitura parcial, insuficiente para relações e recuperação completa |
| Só cloud sync | Rejeitado como backup |
| Backup cloud automático | Futuro, sujeito a retenção, custo e destino independente |

## Ações do utilizador

Guardar cópias fora da app, verificar conteúdo e testar recuperação num ambiente seguro. Não apagar dados originais para “testar se funciona”.

Procedimento: [operação](../guias/07-operacao-backups-e-limites.md).

## Aceitação

E2E-13 do [plano](../plano-e2e.md): dados e fotos recuperados, versão incompatível rejeitada antes de alterar dados, ficheiro corrupto sem importação parcial, histórico sem replay e comportamento explícito sobre conta existente.
