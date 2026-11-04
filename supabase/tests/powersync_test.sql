-- O PowerSync (powersync_role) lê todas as tabelas replicadas e só essas.
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

do $$
declare
  missing text;
  extra text;
begin
  select string_agg(tablename, ', ') into missing
  from pg_publication_tables
  where pubname = 'powersync'
    and not has_table_privilege('powersync_role',
      format('%I.%I', schemaname, tablename), 'select');
  if missing is not null then
    raise exception 'powersync_role sem SELECT em: %', missing;
  end if;

  select string_agg(c.relname, ', ') into extra
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and has_table_privilege('powersync_role', c.oid, 'select')
    and not exists (
      select 1 from pg_publication_tables p
      where p.pubname = 'powersync' and p.schemaname = 'public'
        and p.tablename = c.relname);
  if extra is not null then
    raise exception 'powersync_role lê tabelas fora da publicação: %', extra;
  end if;
end $$;
