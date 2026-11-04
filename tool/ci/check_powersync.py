#!/usr/bin/env python3
"""Confere que as três listas de tabelas sincronizadas coincidem:

- publicação `powersync` nas migrações (o que o Postgres replica);
- streams em powersync/sync-streams.yaml (o que o PowerSync envia);
- tabelas sincronizadas do schema local da app (local_schema.dart; sem as
  de operações, só de envio, nem as locais).

Uma tabela nova que falte numa delas não chega ao outro dispositivo.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def names(text: str) -> set[str]:
    return {n.strip().removeprefix('public.') for n in text.split(',') if n.strip()}


def main() -> int:
    published: set[str] = set()
    for f in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
        sql = re.sub(r'--[^\n]*', '', f.read_text())
        for m in re.finditer(
            r'(?:create|alter)\s+publication\s+powersync\s+(?:for|add)\s+table\s+([^;]+);',
            sql, re.I,
        ):
            published |= names(m.group(1))
        for m in re.finditer(r'alter\s+publication\s+powersync\s+drop\s+table\s+([^;]+);', sql, re.I):
            published -= names(m.group(1))

    yaml = (ROOT / 'powersync/sync-streams.yaml').read_text()
    streamed = set(re.findall(r'query:\s*SELECT\s.+?\sFROM\s+(\w+)', yaml, re.I))

    dart = (ROOT / 'lib/features/account_sync/data/local_schema.dart').read_text()
    local = set(re.findall(r"\bTable\(\s*'(\w+)'", dart))

    ok = True
    for label, other in (('sync-streams.yaml', streamed), ('local_schema.dart', local)):
        if missing := published - other:
            print(f'Na publicação mas não em {label}: {", ".join(sorted(missing))}')
            ok = False
        if extra := other - published:
            print(f'Em {label} mas não na publicação: {", ".join(sorted(extra))}')
            ok = False
    if not published:
        print('Publicação powersync não encontrada nas migrações.')
        ok = False
    if ok:
        print(f'PowerSync coerente: {", ".join(sorted(published))}.')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
