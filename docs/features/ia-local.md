# Feature futura — IA local

Estado: opcional e adiada; nenhum modelo selecionado.

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
