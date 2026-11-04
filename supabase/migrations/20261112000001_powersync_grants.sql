-- Permissões do PowerSync em todas as tabelas replicadas.
--
-- O role powersync_role é criado à mão (docs/guias/08-poc-sincronizacao.md
-- §4) e, nesse passo, só recebia SELECT em garments. Cada tabela que entra
-- na publicação `powersync` precisa também de SELECT para este role; sem
-- isso o PowerSync não consegue ler a tabela e os dados dela não chegam aos
-- outros dispositivos.
--
-- Esta migração dá SELECT em todas as tabelas da publicação. Uma migração
-- que acrescente uma tabela à publicação tem de dar a permissão no mesmo
-- ficheiro (o teste powersync_test.sql falha se faltar). Se o role ainda
-- não existir, não faz nada.

do $$
declare
  t record;
begin
  if not exists (select 1 from pg_roles where rolname = 'powersync_role') then
    raise notice 'powersync_role não existe: sem permissões a dar.';
    return;
  end if;
  execute 'grant usage on schema public to powersync_role';
  for t in
    select schemaname, tablename from pg_publication_tables
    where pubname = 'powersync'
  loop
    execute format('grant select on %I.%I to powersync_role',
      t.schemaname, t.tablename);
  end loop;
end $$;
