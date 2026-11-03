#!/usr/bin/env bash
# Aplica as migrações numa base PostgreSQL temporária e corre os testes SQL.
# Cada ficheiro supabase/tests/*_test.sql corre numa base nova.
# Requer psql e um servidor acessível (variáveis PG* habituais).
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="guarda_roupa_test_$$"
trap 'dropdb --if-exists "$DB"' EXIT
for t in supabase/tests/*_test.sql; do
  dropdb --if-exists "$DB"
  createdb "$DB"
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/supabase_stub.sql
  for f in supabase/migrations/*.sql; do
    psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
  done
  echo "== $t"
  psql -q -o /dev/null -v ON_ERROR_STOP=1 -d "$DB" -f "$t"
done
