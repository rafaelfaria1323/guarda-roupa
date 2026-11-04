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

Levantamento de fontes públicas, a confirmar em cada model card original antes de usar (os números vêm em parte de conversões de terceiros). Nada disto foi descarregado nem medido.

### Runtime

`flutter_onnxruntime` (MIT; 1.9.0 em outubro de 2026): Android, iOS (mínimo iOS 16, ligação estática) e Web. Na Web a app escolhe a versão de `onnxruntime-web` por uma tag em `web/index.html`; sem FP16 na Web por agora. O WASM do `onnxruntime-web` pesa cerca de 27 MB, a somar ao modelo.

### Tarefas, por ordem de utilidade

| # | Tarefa | Sem modelo (baseline) | Candidatos | Licença (a confirmar) | Tamanho aproximado |
|---|---|---|---|---|---|
| 1 | Cores da peça | Contagem de cores da foto, mapeadas às cores de referência; ignora o fundo pela borda. **Implementado como sugestão** ([fotografias](fotografias-e-ficheiros.md)) | — | — | — |
| 2 | Recortar o fundo (melhora as cores, a futura textura do [manequim 3D](manequim-3d.md) e as miniaturas) | Fundo estimado pela borda (já usado nas cores) | U²-Netp; ISNet general; BiRefNet lite | U²-Net/ISNet Apache-2.0; BiRefNet MIT. **Evitar RMBG-1.4/2.0** (Bria: não comercial sem acordo) | U²-Netp ≈ 4,6 MB (320×320); ISNet e BiRefNet lite na ordem das centenas de MB em FP32, menos quantizados |
| 3 | Sugerir a categoria | Escolha manual (atual) | Marqo FashionCLIP (zero-shot: comparar a foto com textos "t-shirt", "calças", …) | Apache-2.0 | Encoder de imagem ≈ 345 MB FP32, ≈ 87 MB int8; os textos das categorias calculam-se uma vez |
| 4 | Inspirações parecidas com peças próprias | Etiquetas confirmadas (atual) | O mesmo FashionCLIP (semelhança de embeddings) | Apache-2.0 | Reutiliza o modelo da tarefa 3 |

Postos de parte:
- **MobileCLIP (Apple):** licença dos pesos própria e, na versão 2, só para investigação.
- **Modelos treinados no DeepFashion:** dataset descrito como só para investigação não comercial.
- **APIs cloud:** custo por chamada, privacidade das fotos e dependência de rede.

### POC proposta (só depois de o utilizador aprovar)

1. **Tarefa 2 com U²-Netp:** o modelo é pequeno o bastante para ir com a app ou descarregar uma vez. Medir com 20–30 fotos reais autorizadas, com fundos variados:
   - qualidade do recorte;
   - tempo por foto no Android, no iPhone (PWA) e no Chromium;
   - memória;
   - se as cores sugeridas melhoram face à baseline da borda.
2. **Tarefa 3 com FashionCLIP int8:** medir a precisão da categoria no mesmo conjunto (top-1 e top-3 por categoria) e o download (≈ 87 MB mais o WASM). Avançar só se acertar o bastante para poupar toques. Se não, fica a escolha manual.
3. **Gate:** a app tem de continuar a funcionar sem o modelo. Isto inclui download recusado, interrompido e offline (E2E-19). As sugestões ficam sempre por confirmar.
4. **Alojamento:** o modelo não vai no repositório. Ir com a app, ou num bucket com cache local, decide-se na POC com os limites do plano Free ([custos](../custos-e-limitacoes.md)).

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

E2E-19 do [plano](../plano-e2e.md), apenas quando esta etapa existir: download recusado/interrompido, inferência útil, correção, offline e continuidade sem modelo.

Ver [fontes](../fontes.md), [motor](motor-de-combinacoes.md) e P-14.

Fontes do levantamento: [flutter_onnxruntime](https://pub.dev/packages/flutter_onnxruntime), [rembg](https://github.com/danielgatis/rembg) (modelos e licenças), [Marqo FashionCLIP](https://huggingface.co/Marqo/marqo-fashionCLIP), [MobileCLIP](https://github.com/apple/ml-mobileclip).
