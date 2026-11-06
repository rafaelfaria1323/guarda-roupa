# Feature — Fotografias e ficheiros

Estado: implementada (2026-11-03) sem recorte; compatibilidade iPhone/HEIC é gate antes de uso real.

## Implementação atual

- Câmara ou galeria (`image_picker`), até 5 fotos por peça; cancelar não faz nada.
- Aceita JPEG, PNG e WebP (formato real, não a extensão). HEIC tem mensagem própria com a alternativa JPEG; ficheiros > 40 MB ou > 64 MP são recusados antes de descodificar.
- Processamento no cliente (`photo_processor.dart`): orientação EXIF aplicada, 1600 px + miniatura 320 px, JPEG sem EXIF/GPS/ICC, transparência sobre branco. Testado com imagens geradas, não com fotos reais de aparelho.
- Bytes guardados primeiro neste dispositivo (SQLite `photo_files`), depois enviados para o bucket privado antes de a foto ser ligada no servidor. Uma falha no envio deixa a operação na fila; a cópia local nunca é apagada por isso.
- No outro dispositivo, a foto é descarregada quando é mostrada, verificada (SHA-256) e guardada para uso offline. Sem rede nem cópia, aparece um marcador.
- Remover desliga a foto; os ficheiros são apagados depois de o servidor aceitar. Eliminar a peça faz o mesmo com todas as fotos dela.
- **Cores pela foto** (2026-11-04, sem modelo: baseline da [IA local](ia-local.md)). No formulário, "Sugerir pela foto" aparece quando a peça tem foto. Lê a miniatura da capa, reduzida a 64 px (`photo_colors.dart`):
  - cada píxel vai para a cor de referência mais próxima em OKLab;
  - com o modelo de recorte neste dispositivo (Definições › IA local), só contam os píxeis que a máscara do U²-Netp marca como peça; a máscara ignora-se se marcar menos de 2 % ou mais de 98 % da foto, e se o recorte falhar segue-se sem ele;
  - sem máscara, o fundo estima-se pela moldura exterior: a cor típica da borda (mediana em Oklab) conta como fundo se ≥ 60 % da borda estiver a menos de 0,06 dela, o que apanha fundos de estúdio em gradiente (por exemplo bege a creme, como nas fotos da Massimo Dutti); tiram-se os píxeis próximos dessa cor, desde que sobrem ≥ 15 % da imagem. Se a borda não tiver cor típica, vale a regra antiga (a cor de referência com ≥ 60 % da borda). Se sobrar pouco, a peça é da cor do fundo e fica;
  - ficam até 3 cores com ≥ 10 %, em passos de 10 % a somar 100 %.

  As sugestões substituem as cores atuais, com "Desfazer", e ficam marcadas "sugerida" (`confirmed: false`) até se tocar em "Confirmar cores" ou se ajustar cada uma. Guardar sem confirmar mantém-nas como sugestão; com recorte, a mensagem diz "sem o fundo da foto". Sombras, reflexos e fundos com várias cores enganam (menos com o recorte); testado com imagens geradas, não com fotos reais.
- O mesmo bucket e o mesmo pipeline servem a imagem opcional das inspirações ([inspirações](inspiracoes-e-estilo.md)), na mesma estrutura `{uid}/{id}/main.jpg|thumb.jpg`.

Limitações conhecidas: sem recorte (`crop_your_image` adiado); sem recuperação da foto se o Android matar a atividade durante a câmara (`retrieveLostData`); fotos descarregadas e depois removidas noutro dispositivo ficam em cache local até terminar sessão.

## Objetivo

Fotografar ou selecionar uma peça, recortar, confirmar e preservar a imagem em ambos os dispositivos, inclusive depois de fechar a app.

## Pipeline recomendado

1. Capturar/selecionar com `image_picker`.
2. Validar formato real, tamanho e dimensões antes de operações dispendiosas.
3. Corrigir orientação e permitir recorte com `crop_your_image`.
4. Produzir versão otimizada e miniatura, preservando um original apenas se houver motivo aprovado.
5. Remover metadados desnecessários, incluindo localização, por um processo verificado.
6. Persistir bytes, criar `MediaAsset` e ligar à peça.
7. Enviar para bucket privado; sincronizar estado e permitir descarregar no outro dispositivo.

Dimensões de 1600 px para a imagem principal e 320 px para miniaturas são **pontos de partida propostos**, não métricas já validadas. Medir legibilidade, memória e espaço antes de fixar.

## Diferenças de plataforma

| Android | PWA/iPhone |
|---|---|
| Copiar resultado temporário para pasta privada persistente | Persistir bytes em IndexedDB; um blob URL é temporário |
| Recuperar resultado perdido se o sistema matar a atividade | Permissões/captura dependem do browser |
| Isolates podem executar processamento fora da UI | Não assumir que `image`/`compute()` usa outra thread |
| Validar formatos realmente devolvidos pelo picker | Testar fotos de iPhone, orientação e HEIC no aparelho real |

Não assumir que a biblioteca Dart `image` descodifica HEIC. Se a plataforma não normalizar o ficheiro, oferecer erro claro e alternativa JPEG; não guardar uma imagem vazia.

## Persistência e cloud

`AssetStore` tem implementações nativa e Web. O repositório conhece IDs de assets, não paths de plataforma expostos aos widgets.

Uploads idempotentes, ficheiros imutáveis e estado pendente evitam substituir parcialmente fotos existentes. Interromper upload não deve apagar a cópia local.

URLs assinadas expiram. Não guardá-las como a única forma de recuperar uma imagem. Políticas de Storage restringem utilizador e operação.

## Alternativas

| Opção | Decisão e motivo |
|---|---|
| Processar e guardar no cliente | Recomendado: menor tráfego e sem serviço pago de imagens |
| Processamento cloud | Pode uniformizar formatos, mas acrescenta CPU, transferências e dados pessoais |
| Base64 em colunas SQL | Rejeitado como padrão: aumenta payloads e mistura ficheiros com queries |
| Apenas links de lojas | Não garante persistência nem direitos; links podem expirar |
| Remoção automática de fundo | Adiada: modelo, peso, qualidade e execução Web precisam de POC |

Não depender de IA de fundo para permitir adicionar uma peça.

## Falhas e ações

Tratar permissão recusada, cancelamento, ficheiro inválido, memória/space insuficientes e quota cloud separadamente. Cancelar o picker não é uma falha que justifique criar uma peça incompleta automaticamente.

Se necessário, criar uma cópia JPEG no Mac em Pré-visualização: abrir a imagem, **Ficheiro > Exportar**, selecionar JPEG e guardar uma cópia com novo nome. Não apagar o original. Esta é uma alternativa manual, não uma conversão já implementada na app.

## Aceitação

E2E-02, E2E-11 e E2E-15 do [plano](../plano-e2e.md): foto real, rotação correta, reabertura offline, outro dispositivo, upload interrompido, quota e formatos do iPhone. Fontes: [registo](../fontes.md); contexto: [ADR-006](../decisoes/006-ficheiros-pwa-e-backups.md).
