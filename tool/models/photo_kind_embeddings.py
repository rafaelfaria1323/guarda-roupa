"""Textos para escolher a foto da loja que mostra só a peça (IA local).

Calcula, com o encoder de texto do Marqo FashionCLIP (ONNX, FP32), dois
embeddings: "pessoa a vestir" e "peça sozinha", cada um a média
normalizada de vários textos em inglês. A importação compara cada foto da
loja com os dois (diferença de cossenos) e fica com a primeira que passe
de THRESHOLD. Escreve assets/models/fashionclip_photo_kind.json.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install onnxruntime numpy tokenizers
    /tmp/venv/bin/python -I tool/models/photo_kind_embeddings.py <dir com text_model.onnx e tokenizer.json>

Medido a 2026-11-07 com o encoder de imagem q4 em 208 fotos de lojas
(DeepFashion In-shop e Polyvore, via Marqo no Hugging Face): AUC 0,93
com as etiquetas do conjunto; revistos os erros, só 2 fotos foram mal
classificadas (costas de um vestido vestido), o resto eram etiquetas erradas.

Ficheiros (revisão 44f4c655124ed71e90cbf528d82f508d69d8a81b):
https://huggingface.co/Marqo/marqo-fashionCLIP/tree/44f4c655124ed71e90cbf528d82f508d69d8a81b
"""
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

REVISION = '44f4c655124ed71e90cbf528d82f508d69d8a81b'
WORN = [
    'a photo of a model wearing clothing',
    'a full body photo of a person',
    'a photo of a person posing',
    'a close-up of a person wearing a garment',
]
ALONE = [
    'a photo of a garment alone',
    'a flat lay photo of a garment',
    'a product photo of a garment, no model',
    'a garment on a plain background',
    'an invisible mannequin product photo',
    'shoes on a white background',
]
# Acima disto (cosseno com "sozinha" menos cosseno com "vestida"), a foto
# conta como só a peça. Um pouco acima do melhor ponto medido (0,012), para
# errar para o lado de olhar mais uma foto.
THRESHOLD = 0.02
CONTEXT = 77
EOT = 49407


def main(model_dir: str) -> None:
    tok = Tokenizer.from_file(f'{model_dir}/tokenizer.json')
    text = ort.InferenceSession(f'{model_dir}/text_model.onnx')

    def embed(s: str) -> np.ndarray:
        ids = tok.encode(s).ids[:CONTEXT]
        ids += [EOT] * (CONTEXT - len(ids))
        e = text.run(None, {'input_ids': np.array([ids], np.int64)})[0][0]
        return e / np.linalg.norm(e)

    def mean(phrases: list[str]) -> list[float]:
        m = np.mean([embed(p) for p in phrases], 0)
        return [round(float(v), 6) for v in m / np.linalg.norm(m)]

    path = Path(__file__).resolve().parents[2] / 'assets/models/fashionclip_photo_kind.json'
    path.write_text(json.dumps({
        'model': 'Marqo/marqo-fashionCLIP',
        'revision': REVISION,
        'texts': {'worn': WORN, 'alone': ALONE},
        'threshold': THRESHOLD,
        'worn': mean(WORN),
        'alone': mean(ALONE),
    }, ensure_ascii=False) + '\n')
    print(path)


if __name__ == '__main__':
    main(sys.argv[1])
