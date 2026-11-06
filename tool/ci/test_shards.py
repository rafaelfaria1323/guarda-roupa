"""Calcula a divisão de testes em shards que minimiza o tempo total da CI.

Cada shard paga um custo fixo de arranque (checkout, Flutter, pub get), por
isso mais shards nem sempre é mais rápido. O script:

1. Estima o custo de cada ficheiro de teste (compilação + nº de testes).
2. Para n = 1..MAX_SHARDS distribui os ficheiros pelo algoritmo LPT
   (maior primeiro, para o shard menos carregado) e estima o tempo de parede
   como SETUP_S + carga do shard mais pesado.
3. Escolhe o menor n a partir do qual um shard extra já não poupa pelo
   menos MIN_GAIN_S segundos (evita gastar runners por ganhos marginais).

Saída (GITHUB_OUTPUT): `matrix` com a lista de ficheiros de cada shard e
`total` com o número de shards.

As constantes são estimativas e podem ser ajustadas por variável de ambiente
quando houver tempos reais medidos na CI.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys


def env_float(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


# Medido na CI a 2026-11-06 (PR #59, 54 ficheiros, 348 testes): arranque
# ~20 s com a cache do Flutter, `flutter test` ~153 s num só shard.
SETUP_S = env_float("SHARD_SETUP_S", 20)  # arranque de um job de testes
FILE_S = env_float("TEST_FILE_S", 9)  # compilar/carregar um ficheiro
WIDGET_TEST_S = env_float("WIDGET_TEST_S", 1.5)
UNIT_TEST_S = env_float("UNIT_TEST_S", 0.06)
CONCURRENCY = env_float("TEST_CONCURRENCY", 4)  # flutter test -j (vCPUs)
MIN_GAIN_S = env_float("MIN_GAIN_S", 30)
MAX_SHARDS = int(os.environ.get("MAX_SHARDS", "8"))

WIDGET = re.compile(r"^\s*testWidgets\s*\(", re.MULTILINE)
UNIT = re.compile(r"^\s*test\s*\(", re.MULTILINE)


def file_costs(root: pathlib.Path) -> dict[str, float]:
    costs = {}
    for path in sorted(root.rglob("*_test.dart")):
        source = path.read_text(encoding="utf-8")
        widgets = len(WIDGET.findall(source))
        units = len(UNIT.findall(source))
        costs[path.as_posix()] = FILE_S + widgets * WIDGET_TEST_S + units * UNIT_TEST_S
    return costs


def pack(costs: dict[str, float], shards: int) -> list[tuple[float, list[str]]]:
    """LPT: ficheiro mais caro primeiro, para o shard com menos carga."""
    bins: list[tuple[float, list[str]]] = [(0.0, []) for _ in range(shards)]
    for name, cost in sorted(costs.items(), key=lambda kv: (-kv[1], kv[0])):
        i = min(range(shards), key=lambda k: bins[k][0])
        load, files = bins[i]
        bins[i] = (load + cost, files + [name])
    return bins


def wall_time(bins: list[tuple[float, list[str]]]) -> float:
    return SETUP_S + max(load for load, _ in bins) / CONCURRENCY


def choose(costs: dict[str, float]) -> list[tuple[float, list[str]]]:
    limit = max(1, min(MAX_SHARDS, len(costs)))
    best = pack(costs, 1)
    for n in range(2, limit + 1):
        candidate = pack(costs, n)
        if wall_time(best) - wall_time(candidate) < MIN_GAIN_S:
            break
        best = candidate
    return best


def main() -> int:
    costs = file_costs(pathlib.Path("test"))
    if not costs:
        print("Sem ficheiros de teste.", file=sys.stderr)
        return 1

    bins = choose(costs)
    print(f"{len(costs)} ficheiro(s) de teste -> {len(bins)} shard(s)")
    for i, (load, files) in enumerate(bins):
        print(f"  shard {i + 1}: {len(files)} ficheiro(s), ~{load / CONCURRENCY:.0f}s de testes")
    print(f"  tempo de parede estimado: ~{wall_time(bins):.0f}s")

    matrix = {
        "include": [
            {"shard": i + 1, "files": " ".join(files)}
            for i, (_, files) in enumerate(bins)
        ]
    }
    with open(os.environ.get("GITHUB_OUTPUT", os.devnull), "a", encoding="utf-8") as out:
        out.write(f"total={len(bins)}\n")
        out.write(f"matrix={json.dumps(matrix)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
