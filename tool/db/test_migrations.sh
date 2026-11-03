#!/usr/bin/env bash
# Aplica as migrações numa base PostgreSQL temporária e corre os testes SQL.
# Requer psql e um servidor acessível (variáveis PG* habituais).
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="guarda_roupa_test_$$"
createdb "$DB"
trap 'dropdb --if-exists "$DB"' EXIT
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/supabase_stub.sql
for f in supabase/migrations/*.sql; do
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done
psql -q -o /dev/null -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/garments_test.sql
