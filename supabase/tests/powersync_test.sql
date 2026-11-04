-- Os roles do PowerSync (replicação, nome "powersync…") leem todas as
-- tabelas replicadas e só essas. O stub cria powersync_role e, aqui, um
-- segundo role como o que a integração cria; grant_powersync_select()
-- serve os dois.
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'powersync_test_integration') then
    create role powersync_test_integration replication login;
  end if;
end $$;
select public.grant_powersync_select();

do $$
declare
  role text;
  missing text;
  extra text;
begin
  foreach role in array array['powersync_role', 'powersync_test_integration'] loop
  select string_agg(tablename, ', ') into missing
  from pg_publication_tables
  where pubname = 'powersync'
    and not has_table_privilege(role,
      format('%I.%I', schemaname, tablename), 'select');
  if missing is not null then
    raise exception '% sem SELECT em: %', role, missing;
  end if;

  select string_agg(c.relname, ', ') into extra
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and has_table_privilege(role, c.oid, 'select')
    and not exists (
      select 1 from pg_publication_tables p
      where p.pubname = 'powersync' and p.schemaname = 'public'
        and p.tablename = c.relname);
  if extra is not null then
    raise exception '% lê tabelas fora da publicação: %', role, extra;
  end if;
  end loop;
end $$;
