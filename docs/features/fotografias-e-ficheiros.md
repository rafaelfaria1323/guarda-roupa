# Feature — Fotografias e ficheiros

Estado: necessária no MVP; compatibilidade iPhone/HEIC é gate antes de uso real.

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
