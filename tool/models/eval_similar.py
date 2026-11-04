"""Mede "peças parecidas" (FashionCLIP, semelhança imagem-imagem).

Para cada foto do clothing-dataset (CC0), as 5 mais parecidas entre as
outras: quantas têm a mesma etiqueta. Mesmo conjunto e pré-processamento de
eval_category.py:

    /tmp/venv/bin/python -I tool/models/eval_similar.py <clothing-dataset> <modelo .onnx> [por etiqueta=40]
"""
import collections
import csv
import random
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval_category import ACCEPT, pre  # noqa: E402


def main(data: str, model: str, per: int = 40) -> None:
    vision = ort.InferenceSession(model)
    rows = [r for r in csv.DictReader(open(f'{data}/images.csv')) if r['kids'] == 'False' and r['label'] in ACCEPT]
    by = collections.defaultdict(list)
    for r in rows:
        by[r['label']].append(r)
    rnd = random.Random(42)
    labels, embs = [], []
    for label in sorted(by):
        for r in rnd.sample(by[label], min(per, len(by[label]))):
            e = vision.run(None, {'pixel_values': pre(f"{data}/images/{r['image']}.jpg")[None]})[0][0]
            labels.append(label)
            embs.append(e / np.linalg.norm(e))
    x = np.array(embs)
    sim = x @ x.T
    np.fill_diagonal(sim, -2)
    same, diff = [], []
    hits = collections.Counter()
    n = collections.Counter()
    for i, label in enumerate(labels):
        top = np.argsort(-sim[i])[:5]
        hits[label] += sum(labels[j] == label for j in top)
        n[label] += 5
        for j in range(len(labels)):
            if j != i:
                (same if labels[j] == label else diff).append(sim[i, j])
    for label in sorted(n):
        print(f'{label:11s} p@5={hits[label] / n[label]:.2f}')
    print(f'TOTAL p@5={sum(hits.values()) / sum(n.values()):.3f}')
    for name, v in (('mesma', same), ('outra', diff)):
        q = np.percentile(v, [5, 25, 50, 75, 95])
        print(f'cosseno {name}: ' + ' '.join(f'{p:.2f}' for p in q))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 40)
