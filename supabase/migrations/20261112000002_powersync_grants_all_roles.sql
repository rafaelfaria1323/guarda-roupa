-- Permissões do PowerSync, para qualquer role com que ele se ligue.
--
-- Na base real, o PowerSync liga-se com um role criado pela integração
-- (powersync_<id>), não só com o powersync_role do guia 08 §4. Esse role
-- não tinha SELECT em plan_entries e o deploy das Sync Streams falhava com
-- "permission denied for table plan_entries".
--
-- grant_powersync_select() dá SELECT em todas as tabelas da publicação
-- `powersync` a todos os roles de replicação com login cujo nome comece por
-- "powersync". Uma migração que acrescente uma tabela à publicação chama-a
-- no fim (o teste powersync_test.sql falha se faltar).

create or replace function public.grant_powersync_select()
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
  t record;
begin
  for r in
    select rolname from pg_roles
    where rolreplication and rolcanlogin and not rolsuper
      and rolname like 'powersync%'
  loop
    execute format('grant usage on schema public to %I', r.rolname);
    for t in
      select schemaname, tablename from pg_publication_tables
      where pubname = 'powersync'
    loop
      execute format('grant select on %I.%I to %I',
        t.schemaname, t.tablename, r.rolname);
    end loop;
  end loop;
end $$;

revoke all on function public.grant_powersync_select() from public, anon, authenticated;

do $$ begin perform public.grant_powersync_select(); end $$;
