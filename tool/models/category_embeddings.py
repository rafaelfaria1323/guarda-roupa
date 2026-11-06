"""Textos das categorias para a sugestão pela foto (IA local, P-14).

Calcula, com o encoder de texto do Marqo FashionCLIP (ONNX, FP32), um
embedding por categoria da app: a média normalizada de vários textos em
inglês (como no treino). Escreve assets/models/fashionclip_categories.json.
Só é preciso voltar a correr se mudarem as categorias ou os textos.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install onnxruntime numpy tokenizers
    /tmp/venv/bin/python -I tool/models/category_embeddings.py <dir com text_model.onnx e tokenizer.json>

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
TEMPLATES = ['a photo of {}', '{}', 'a photo of {}, clothing']
# Ids de GarmentCategory (lib/features/wardrobe/domain/garment_category.dart).
# "other" fica de fora: nunca se sugere.
CATEGORIES = {
    't_shirt': ['a t-shirt', 'a short-sleeve t-shirt', 'a tee'],
    'shirt': ['a button-up shirt', 'a dress shirt', 'a collared button-down shirt'],
    'polo': ['a polo shirt'],
    'top': ['a tank top', 'a blouse', "a women's top"],
    'sweater': ['a knit sweater', 'a jumper', 'a pullover sweater'],
    'sweatshirt': ['a sweatshirt', 'a hoodie'],
    'cardigan': ['a cardigan'],
    'trousers': ['trousers', 'chino pants', 'dress pants'],
    'jeans': ['jeans', 'denim jeans'],
    'shorts': ['shorts'],
    'skirt': ['a skirt'],
    'dress': ['a dress'],
    'jumpsuit': ['a jumpsuit'],
    'jacket': ['a jacket', 'a bomber jacket', 'a denim jacket'],
    'blazer': ['a blazer', 'a suit jacket'],
    'coat': ['a coat', 'a winter coat', 'a parka'],
    'raincoat': ['a raincoat', 'a rain jacket'],
    'sneakers': ['sneakers', 'trainers'],
    'shoes': ['leather shoes', 'dress shoes', 'heels'],
    'boots': ['boots'],
    'sandals': ['sandals', 'flip-flops'],
    'scarf': ['a scarf', 'a knitted scarf', 'a wool scarf'],
    'beanie': ['a beanie', 'a knit winter hat'],
    'gloves': ['gloves', 'winter gloves', 'leather gloves'],
    'hat': ['a baseball cap', 'a hat', 'a bucket hat'],
    'sunglasses': ['sunglasses'],
    'umbrella': ['an umbrella', 'a folding umbrella'],
    'belt': ['a belt', 'a leather belt'],
    'bag': ['a bag', 'a handbag', 'a backpack', 'a tote bag'],
    'accessory': ['a necktie', 'socks', 'jewelry', 'a wristwatch'],
}
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

    out = {}
    for cid, phrases in CATEGORIES.items():
        m = np.mean([embed(t.format(p)) for p in phrases for t in TEMPLATES], 0)
        out[cid] = [round(float(v), 6) for v in m / np.linalg.norm(m)]
    path = Path(__file__).resolve().parents[2] / 'assets/models/fashionclip_categories.json'
    path.write_text(json.dumps({
        'model': 'Marqo/marqo-fashionCLIP',
        'revision': REVISION,
        'templates': TEMPLATES,
        'texts': CATEGORIES,
        'categories': out,
    }, ensure_ascii=False) + '\n')
    print(path)


if __name__ == '__main__':
    main(sys.argv[1])
