"""Mede a sugestão de categoria (FashionCLIP) em fotos reais com etiqueta.

Conjunto: clothing-dataset de Alexey Grigorev (CC0; fotos tiradas por
pessoas, fora dos datasets de treino do Marqo-FashionCLIP):
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/alexeygrigorev/clothing-dataset

    /tmp/venv/bin/python -I tool/models/eval_category.py <clothing-dataset> <modelo .onnx> [por etiqueta=40]

Usa os textos de assets/models/fashionclip_categories.json. Algumas
etiquetas do dataset valem várias categorias da app ("Pants" = calças ou
jeans; "Shoes" = qualquer calçado).
"""
import collections
import csv
import json
import random
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image

ACCEPT = {
    'T-Shirt': ['t_shirt'], 'Shirt': ['shirt'], 'Polo': ['polo'], 'Top': ['top'],
    'Blouse': ['top', 'shirt'], 'Undershirt': ['top', 't_shirt'], 'Hoodie': ['sweatshirt'],
    'Longsleeve': ['sweater', 'sweatshirt', 'top', 't_shirt', 'shirt', 'cardigan'],
    'Pants': ['trousers', 'jeans'], 'Shorts': ['shorts'], 'Skirt': ['skirt'], 'Dress': ['dress'],
    'Outwear': ['jacket', 'coat', 'raincoat', 'blazer'], 'Blazer': ['blazer'],
    'Shoes': ['sneakers', 'shoes', 'boots', 'sandals'], 'Hat': ['accessory'],
}
MEAN = np.array([0.48145466, 0.4578275, 0.40821073], np.float32)
STD = np.array([0.26862954, 0.26130258, 0.27577711], np.float32)


def pre(path: str) -> np.ndarray:
    im = Image.open(path).convert('RGB')
    w, h = im.size
    s = 224 / min(w, h)
    im = im.resize((max(224, round(w * s)), max(224, round(h * s))), Image.BICUBIC)
    w, h = im.size
    l, t = (w - 224) // 2, (h - 224) // 2
    a = np.asarray(im.crop((l, t, l + 224, t + 224)), np.float32) / 255
    return ((a - MEAN) / STD).transpose(2, 0, 1)


def main(data: str, model: str, per: int = 40) -> None:
    asset = json.loads((Path(__file__).resolve().parents[2] / 'assets/models/fashionclip_categories.json').read_text())
    names = list(asset['categories'])
    texts = np.array([asset['categories'][n] for n in names], np.float32)
    vision = ort.InferenceSession(model)
    rows = [r for r in csv.DictReader(open(f'{data}/images.csv')) if r['kids'] == 'False' and r['label'] in ACCEPT]
    by = collections.defaultdict(list)
    for r in rows:
        by[r['label']].append(r)
    rnd = random.Random(42)
    total = collections.Counter()
    for label in sorted(by):
        c = collections.Counter()
        for r in rnd.sample(by[label], min(per, len(by[label]))):
            e = vision.run(None, {'pixel_values': pre(f"{data}/images/{r['image']}.jpg")[None]})[0][0]
            order = [names[i] for i in np.argsort(-(texts @ (e / np.linalg.norm(e))))]
            c['n'] += 1
            c['top1'] += order[0] in ACCEPT[label]
            c['top3'] += any(o in ACCEPT[label] for o in order[:3])
        total.update(c)
        print(f"{label:11s} n={c['n']:3d} top1={c['top1'] / c['n']:.2f} top3={c['top3'] / c['n']:.2f}")
    print(f"TOTAL n={total['n']} top1={total['top1'] / total['n']:.3f} top3={total['top3'] / total['n']:.3f}")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 40)
