"""Calcula a matriz de shards de testes para a CI.

Conta as declarações test()/testWidgets() em test/ e divide em shards de
~TESTS_PER_SHARD testes (ex.: 300 testes -> 3 shards de 100).
"""
import json
import math
import os
import pathlib
import re

TESTS_PER_SHARD = int(os.environ.get("TESTS_PER_SHARD", "100"))
MAX_SHARDS = int(os.environ.get("MAX_SHARDS", "10"))

pattern = re.compile(r"^\s*(?:test|testWidgets)\s*\(", re.MULTILINE)
count = sum(
    len(pattern.findall(p.read_text(encoding="utf-8")))
    for p in pathlib.Path("test").rglob("*_test.dart")
)
total = max(1, min(MAX_SHARDS, math.ceil(count / TESTS_PER_SHARD)))
matrix = {"shard": list(range(total))}

print(f"{count} testes -> {total} shard(s)")
with open(os.environ.get("GITHUB_OUTPUT", os.devnull), "a", encoding="utf-8") as out:
    out.write(f"total={total}\n")
    out.write(f"matrix={json.dumps(matrix)}\n")
