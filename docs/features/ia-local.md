# Feature futura — IA local

Estado: opcional; nenhum modelo selecionado. Plano da POC e candidatos levantados a 2026-11-04 ([abaixo](#candidatos-e-plano-2026-11-04)); a decisão de avançar com modelos é do utilizador (P-14).

## Casos potencialmente úteis

Sugerir categoria, melhorar recorte/segmentação, extrair atributos visuais e aproximar inspirações de peças próprias por semelhança.

Extração convencional de cores não precisa de ser anunciada como IA. Uma imagem não revela com certeza composição, estado de lavagem ou aquecimento.

## Candidato técnico

`flutter_onnxruntime`, incluindo `onnxruntime-web` na Web. Baseline portátil: WASM/CPU; não assumir WebGPU disponível/acelerado no Safari.

Modelos são dependências distintas: verificar licença de pesos, dados, pré-processamento, operadores, tamanho, RAM, latência e qualidade. Licença do runtime não concede licença do modelo.

## POC necessária

1. Definir tarefa e baseline manual/convencional.
2. Escolher modelo com uso/distribuição permitidos.
3. Testar conjunto representativo de imagens autorizadas.
4. Medir qualidade e falhas por categoria.
5. Medir download, arranque e inferência no Android e iPhone/PWA.
6. Verificar limites do alojamento para pesos e WASM.
7. Só integrar se reduzir esforço de forma útil.

Resultados permanecem sugestões confirmáveis. Falha de IA deixa o formulário manual funcional com aviso, não uma previsão inventada.

## Candidatos e plano (2026-11-04)

Levantamento de fontes públicas, a confirmar em cada model card original antes de usar (os números vêm em parte de conversões de terceiros). O utilizador aprovou a POC completa no mesmo dia; o que já existe está em [POC implementada](#poc-implementada-2026-11-04).

### Runtime

`flutter_onnxruntime` (MIT; 1.9.0 em outubro de 2026): Android, iOS (mínimo iOS 16, ligação estática) e Web. Na Web o plugin precisa do `onnxruntime-web` carregado pela app; sem FP16 na Web por agora. O pacote completo traz WASM de cerca de 22 MB (com WebGPU/JSEP); a variante só WASM, a que se usa, pesa cerca de 11 MB.

### Tarefas, por ordem de utilidade

| # | Tarefa | Sem modelo (baseline) | Candidatos | Licença (a confirmar) | Tamanho aproximado |
|---|---|---|---|---|---|
| 1 | Cores da peça | Contagem de cores da foto, mapeadas às cores de referência; ignora o fundo pela borda. **Implementado como sugestão** ([fotografias](fotografias-e-ficheiros.md)) | — | — | — |
| 2 | Recortar o fundo (melhora as cores, a futura textura do [manequim 3D](manequim-3d.md) e as miniaturas) | Fundo estimado pela borda (já usado nas cores). **U²-Netp implementado nas cores** (POC abaixo) | U²-Netp; ISNet general; BiRefNet lite | U²-Net/ISNet Apache-2.0; BiRefNet MIT. **Evitar RMBG-1.4/2.0** (Bria: não comercial sem acordo) | U²-Netp ≈ 4,6 MB (320×320); ISNet e BiRefNet lite na ordem das centenas de MB em FP32, menos quantizados |
| 3 | Sugerir a categoria | Escolha manual (atual) | Marqo FashionCLIP (zero-shot: comparar a foto com textos "t-shirt", "calças", …) | Apache-2.0 | Encoder de imagem ≈ 345 MB FP32, ≈ 87 MB int8; os textos das categorias calculam-se uma vez |
| 4 | Inspirações parecidas com peças próprias | Etiquetas confirmadas (atual) | O mesmo FashionCLIP (semelhança de embeddings) | Apache-2.0 | Reutiliza o modelo da tarefa 3 |

Postos de parte:
- **MobileCLIP (Apple):** licença dos pesos própria e, na versão 2, só para investigação.
- **Modelos treinados no DeepFashion:** dataset descrito como só para investigação não comercial.
- **APIs cloud:** custo por chamada, privacidade das fotos e dependência de rede.

### POC proposta (aprovada pelo utilizador a 2026-11-04)

1. **Tarefa 2 com U²-Netp:** o modelo é pequeno o bastante para ir com a app ou descarregar uma vez. Medir com 20–30 fotos reais autorizadas, com fundos variados:
   - qualidade do recorte;
   - tempo por foto no Android, no iPhone (PWA) e no Chromium;
   - memória;
   - se as cores sugeridas melhoram face à baseline da borda.
2. **Tarefa 3 com FashionCLIP int8:** medir a precisão da categoria no mesmo conjunto (top-1 e top-3 por categoria) e o download (≈ 87 MB mais o WASM). Avançar só se acertar o bastante para poupar toques. Se não, fica a escolha manual.
3. **Gate:** a app tem de continuar a funcionar sem o modelo. Isto inclui download recusado, interrompido e offline (E2E-19). As sugestões ficam sempre por confirmar.
4. **Alojamento:** o modelo não vai no repositório. Ir com a app, ou num bucket com cache local, decide-se na POC com os limites do plano Free ([custos](../custos-e-limitacoes.md)).

## POC implementada (2026-11-04)

**Recorte de fundo com U²-Netp — feito:**

- **Modelo:** `u2netp.onnx` da release `v0.0.0` do [rembg](https://github.com/danielgatis/rembg/releases/tag/v0.0.0). São 4 574 861 bytes, com sha256 `309c8469…4ddd8` fixo em `lib/features/local_ai/domain/local_model.dart`. Pesos Apache-2.0 ([U-2-Net](https://github.com/xuebinqin/U-2-Net)).
  - Entrada `input.1` `[1, 3, 320, 320]`, como no rembg: divide-se pelo máximo e normaliza-se com média e desvio do ImageNet.
  - Usa-se a primeira de 7 saídas `[1, 1, 320, 320]`, normalizada para 0–1. É peça se ≥ 0,5.
- **Descarga só a pedido:** Definições › IA local mostra o tamanho e a licença e tem "Descarregar" e "Remover".
  - Confirma tamanho e sha256 antes de o modelo ficar pronto.
  - Descarga recusada, interrompida ou com ficheiro errado: nada fica a meio, aparece aviso e pode tentar-se de novo.
  - Sem modelo, tudo funciona como antes (E2E-19).
- **Onde fica:**
  - **Android/iOS:** ficheiro no diretório de suporte da app, descarregado do GitHub.
  - **Web:** a PWA serve o modelo da própria origem em `models/`, porque o GitHub não manda cabeçalhos CORS. O `onnxruntime-web` 1.22.0 (só WASM) vem em `ort/`, também da própria origem, sem CDN de terceiros. Só se carrega no primeiro uso.
  - Os dois vão para `web/` com `tool/models/fetch_models.sh`, que confirma o sha256 do modelo e a integridade npm do runtime. Não são versionados.
  - O acordo fica no `localStorage` e o ficheiro na cache do browser.
  - Todos os ficheiros ficam abaixo do limite de 25 MiB por ficheiro do Pages ([custos](../custos-e-limitacoes.md#ia-local)).
- **Uso:** "Sugerir pela foto" corre o recorte na miniatura da capa e conta só a peça ([fotografias](fotografias-e-ficheiros.md)). As cores ficam sempre por confirmar.

**Medido até agora (só imagens sintéticas):**

| Teste | Resultado |
|---|---|
| Camisa vermelha num fundo bege em gradiente com ruído, onnxruntime em Python e com o pré-processamento Dart | IoU da máscara 0,997 e 0,994 |
| Mesma foto, só a borda (sem modelo) | 40 % vermelho, 40 % bege, 20 % caqui |
| Mesma foto, com a máscara | 100 % vermelho |
| Retângulo vermelho em gradiente, build Web real no Chromium headless (plugin → `ort/` → `models/`) | Máscara com 36 % da foto (o retângulo ocupa 36 %), cores 100 % vermelho; cerca de 2 s no primeiro uso, incluindo abrir a sessão |

**Por medir** (precisa de aparelho e fotos reais): qualidade com 20–30 fotos reais, tempo e memória no Android e no iPhone (PWA). Os testes automáticos usam um recorte falso: não há runtime ONNX nos testes de widgets.

**Sugestão de categoria (FashionCLIP) — por fazer:** os pesos estão no Hugging Face, que a rede do ambiente de desenvolvimento ainda não deixa usar. Sem eles não se mede a precisão (o gate da tarefa 3), por isso não se implementou nada a fingir. Com acesso, os passos são:

1. confirmar a licença no model card;
2. exportar ou obter o encoder de imagem int8 e os embeddings dos textos das categorias;
3. medir top-1 e top-3;
4. só se acertar o bastante, mostrar a categoria sugerida, por confirmar.

## Alternativas

| Opção | Avaliação |
|---|---|
| ONNX local | Candidato recomendado: possibilidade de runtime comum, com POC obrigatória |
| TFLite nativo | Alternativa forte no mobile; integração Web tem de ser resolvida separadamente |
| ML Kit | Conveniente para certas tarefas mobile, mas não uma solução Flutter Web equivalente |
| Modelos cloud | Capacidade superior possível, mas privacidade/custo e dependência de rede |
| Sem modelo | Abordagem inicial escolhida; atributos assistidos já permitem produto útil |

## Ações e aceitação

O utilizador aprova download/uso de modelos e confirma sugestões. Não é pedido cartão nem API key paga como pré-requisito.

E2E-19 do [plano](../plano-e2e.md): download recusado/interrompido, inferência útil, correção, offline e continuidade sem modelo. Coberto por testes de widgets com modelo e recorte falsos (descarga a pedido, progresso, falha, remoção; recorte que falha cai na borda). Falta o E2E em aparelho.

Ver [fontes](../fontes.md), [motor](motor-de-combinacoes.md) e P-14.

Fontes do levantamento: [flutter_onnxruntime](https://pub.dev/packages/flutter_onnxruntime), [rembg](https://github.com/danielgatis/rembg) (modelos e licenças), [Marqo FashionCLIP](https://huggingface.co/Marqo/marqo-fashionCLIP), [MobileCLIP](https://github.com/apple/ml-mobileclip).
