# Feature — Backups e recuperação

Estado: necessária na base utilizável; recuperação sobre conta sincronizada existente exige protocolo aprovado.

Implementado (2026-11-03): exportação e verificação do formato v1.

- **Conteúdo:** `manifest.json` (formato, versão, `exported_at`, contagens, `pending_operations` e a lista de ficheiros com caminho, MIME, tamanho e SHA-256), `data/garments.json` com as colunas do servidor, sem `owner_id`, e `photos/{id}/main.jpg|thumb.jpg`.
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

Por fazer: aplicar a recuperação num destino vazio, com escolha do ficheiro e preview.

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
