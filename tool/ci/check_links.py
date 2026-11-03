"""Falha se algum link relativo nos .md apontar para um ficheiro inexistente."""
import pathlib
import re
import sys

link = re.compile(r"\]\(([^)#\s]+)(?:#[^)]*)?\)")
broken = []
for md in pathlib.Path(".").rglob("*.md"):
    if any(part.startswith(".") or part == "build" for part in md.parts):
        continue
    for target in link.findall(md.read_text(encoding="utf-8")):
        if "://" in target or target.startswith("mailto:"):
            continue
        if not (md.parent / target).exists():
            broken.append(f"{md}: {target}")

print("\n".join(broken) or "Sem links partidos.")
sys.exit(1 if broken else 0)
