# Feature — Backups e recuperação

Estado: necessária na base utilizável. Recuperação por cima de uma conta com dados: **juntar** (P-11, decidido pelo utilizador a 2026-11-06), implementado.

Implementado (2026-11-03): exportação e verificação do formato v5 (lê também v1 a v4).

- **Conteúdo:** `manifest.json` (formato, versão, `exported_at`, contagens, `pending_operations` e a lista de ficheiros com caminho, MIME, tamanho e SHA-256), `data/garments.json` com as colunas do servidor, sem `owner_id`, `data/history.json` (desde a v2), `data/outfits.json` (desde a v3), `data/style.json` (desde a v4) e `photos/{id}/main.jpg|thumb.jpg` (fotografias das peças e, desde a v5, imagens das inspirações).
- **Histórico (v2):** utilizações (“Vesti hoje”) e limpezas ativas — as desfeitas ficam de fora — e os valores de lavagem/rotatividade escolhidos por categoria e por peça. Só entra o que refere peças exportadas: uma utilização com uma peça entretanto eliminada fica só com as restantes. O plano (`plan_entry_id`) não entra. Um backup v1 continua a ser lido (sem histórico); um v2 sem `data/history.json`, ou com histórico que refira peças que não estão no ficheiro, datas inválidas ou valores fora dos limites, é rejeitado por inteiro.
- **Conjuntos (v3):** os conjuntos guardados ativos, com nome, ocasiões e peças/papéis. Peças eliminadas saem do conjunto; um conjunto que fique sem peças fica de fora. Peças arquivadas mantêm-se. Na recuperação, os conjuntos ganham ids novos e apontam para as peças novas (`create_outfit`). Um v2 continua a ser lido (sem conjuntos); um v3 sem `data/outfits.json`, ou com um conjunto inválido (as mesmas regras do servidor) ou que refira peças que não estão no ficheiro, é rejeitado por inteiro.
- **Estilo (v4):** as inspirações (com proporções; um v4 sem `proportions` lê-se como "nenhuma") e as preferências de estilo ativas. Uma preferência cuja inspiração já foi eliminada vai sem origem. Na recuperação ganham ids novos e a origem aponta para a inspiração nova (`create_inspiration`, `create_preference`). O destino pode já ter estilo: uma inspiração igual reutiliza-se e uma preferência com o mesmo assunto, valor e contexto não se repete (fica a do destino). Um v3 continua a ser lido (sem estilo); um v4 sem `data/style.json`, ou com uma inspiração ou preferência inválida (as mesmas regras do servidor) ou com uma origem que não está no ficheiro, é rejeitado por inteiro.
- **Imagens das inspirações (v5):** cada inspiração leva o objeto `image` (ou `null`) e os ficheiros em `photos/`, verificados como as fotos das peças (tamanho e SHA-256); uma imagem em falta, alterada ou ficheiros sem dono rejeitam o ficheiro. Sobe para v5 porque um leitor v4 recusaria esses ficheiros. Na exportação, uma imagem que não está neste dispositivo é descarregada; se não for possível, a exportação falha como nas fotos. Na recuperação a imagem ganha id novo, fica neste dispositivo e segue como `set_inspiration_image` depois de `create_inspiration` (a fila envia os ficheiros antes). Uma inspiração reutilizada (igual a uma do destino) fica com a imagem que já tinha. O preview diz quantas imagens de inspirações traz; não contam como fotografias de peças. Um v4 continua a ser lido (sem imagens).
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

Recuperação (juntar ao que a conta tem; P-11, 2026-11-06):

- **Percurso:** Definições › Recuperar backup › escolher o ZIP (`file_selector`).
- **Antes de mostrar o preview, valida o ficheiro** com o leitor acima. Com cloud, a primeira sincronização tem de ter terminado, porque antes disso não se sabe o que a conta tem.
- **Juntar, nunca substituir:** só se acrescenta o que falta. O que a conta já tem fica como está, mesmo que tenha sido editado depois do backup (estado, fotos, nome, valores de lavagem/rotatividade). Nada é apagado.
- **Peças já na conta:** são reconhecidas pelo mesmo id ou, se já tinham sido recuperadas antes com id novo, pela mesma data de criação, categoria e nome. Ficam como estão, e o histórico do backup liga-se a elas.
- **Sem ressurreição silenciosa:**
  - peças apagadas nesta conta depois do backup aparecem no preview com uma caixa “Recuperar também N peças apagadas depois do backup”. Desmarcada numa conta com peças; marcada numa conta vazia, porque quem esvazia a conta para recuperar quer tudo de volta. Se forem recuperadas, ganham id novo;
  - utilizações e limpezas desfeitas, e conjuntos, inspirações e preferências apagados depois do backup, não voltam.
  - Como as linhas apagadas saem do stream do PowerSync, a app pergunta ao Supabase (com a RLS do utilizador) que ids do backup estão apagados ou desfeitos, e junta o que ainda está neste dispositivo por enviar. Sem rede, numa conta com peças, recusa e pede rede; numa conta vazia segue (é o primeiro modo de antes).
- **Sem duplicar:** uma utilização, limpeza ou conjunto com o mesmo id não se repete. Também não se repete quando a conta já tem o mesmo conteúdo com as mesmas peças: uma utilização no mesmo dia com as mesmas peças, uma limpeza da mesma peça no mesmo dia, um conjunto com as mesmas peças e papéis. Inspirações iguais e preferências com o mesmo alvo também não se repetem. Uma utilização ou conjunto com peças apagadas que não se recuperam fica só com as restantes, e sai se ficar sem nenhuma.
- **Preview:**
  - data;
  - peças e fotografias novas, e quantas já estão na conta;
  - a caixa das peças apagadas;
  - o que entra de histórico, conjuntos, estilo e imagens das inspirações;
  - as alterações que ainda não estavam sincronizadas na exportação.
  - As contagens mudam com a caixa. Se não houver nada a acrescentar, o preview diz isso e o botão fica desligado.
- **Aplicação:**
  - acontece só depois de confirmar e corre numa única transação;
  - a comparação com a conta repete-se dentro da transação, por isso o que mudou desde o preview conta, e confirmar duas vezes não duplica nada;
  - o histórico é recriado na mesma transação pela ordem original de registo (o servidor mantém a ordem entre uma utilização e uma limpeza do mesmo dia) e segue pela fila normal depois das peças.
- **IDs novos para o que é criado (peças, fotografias, histórico):** nada ressuscita um id apagado nem colide com IDs que o servidor já conhece.
  - Mantém a data de criação original.
  - O estado (disponibilidade, arquivo) e as fotografias entram como operações normais: `create`, `set_availability`, `attach_photo`, `archive`. A fila envia os ficheiros antes de ligar as fotos.

Fora do âmbito: substituir (apagar a conta e pôr o backup no lugar). Não foi pedido; para isso, apagar as peças à mão e recuperar.

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

Recuperar por cima de uma conta com dados não é “apagar a base local e voltar a sincronizar”: junta-se pelas regras acima (P-11). Não propagar eventos antigos como novas utilizações, restaurar tokens ou ressuscitar deletes em segredo.

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
