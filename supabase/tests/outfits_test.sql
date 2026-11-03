-- Testes de conjuntos guardados (apply_outfit_operation).
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'eu@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'outra@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
insert into public.allowed_users (email) values ('eu@example.com'), ('outra@example.com');

create function pg_temp.as_user(sub text, email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', sub, 'email', email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.garment(op_id text, garment text) returns jsonb
language sql as $$
  select public.apply_garment_operation(jsonb_build_object(
    'op_id', op_id, 'garment_id', garment, 'kind', 'create',
    'data', '{"category":"t_shirt"}'::jsonb));
$$;

create function pg_temp.outfit(op_id text, kind text, data jsonb,
  outfit text default 'd0000000-0000-0000-0000-000000000001') returns jsonb
language sql as $$
  select public.apply_outfit_operation(jsonb_build_object(
    'op_id', op_id, 'outfit_id', outfit, 'kind', kind, 'data', data));
$$;

create function pg_temp.items(variadic pairs text[]) returns jsonb
language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('garment_id', pairs[i], 'role', pairs[i + 1])
    order by i), '[]'::jsonb)
  from generate_series(1, array_length(pairs, 1), 2) as i;
$$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

\set A '00000000-0000-0000-0000-00000000000a'
\set G1 '10000000-0000-0000-0000-000000000001'
\set G2 '10000000-0000-0000-0000-000000000002'
\set G3 '10000000-0000-0000-0000-000000000003'
\set GB '10000000-0000-0000-0000-0000000000b1'
\set O1 'd0000000-0000-0000-0000-000000000001'
\set O2 'd0000000-0000-0000-0000-000000000002'

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.garment('20000000-0000-0000-0000-000000000001', :'G1');
select pg_temp.garment('20000000-0000-0000-0000-000000000002', :'G2');
select pg_temp.garment('20000000-0000-0000-0000-000000000003', :'G3');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.garment('20000000-0000-0000-0000-000000000004', :'GB');
commit;

-- ------------------------------------------------------------------ criar
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.outfit('30000000-0000-0000-0000-000000000001', 'create_outfit',
  jsonb_build_object('name', 'Sexta', 'occasions', '["casual","evening"]'::jsonb,
    'items', pg_temp.items(:'G1', 'main_top', :'G2', 'bottom', :'G3', 'footwear'))) as r \gset
select pg_temp.check('cria conjunto t-shirt + calças + ténis, sem casaco',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select name = 'Sexta' and jsonb_array_length(items) = 3
         and occasions = '["casual","evening"]' and owner_id = auth.uid()
       from public.outfits where id = :'O1'));
select pg_temp.outfit('30000000-0000-0000-0000-000000000001', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'G1', 'main_top'))) as r \gset
select pg_temp.check('repetir op_id devolve o mesmo e não duplica',
  :'r'::jsonb ->> 'result' = 'applied' and (select count(*) = 1 from public.outfits));
select pg_temp.outfit('30000000-0000-0000-0000-000000000002', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'G1', 'main_top'))) as r \gset
select pg_temp.check('mesmo id: already_exists', :'r'::jsonb ->> 'reason' = 'already_exists');

select pg_temp.outfit('30000000-0000-0000-0000-000000000003', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'G1', 'main_top', :'G1', 'mid_layer')), :'O2') as r \gset
select pg_temp.check('a mesma peça duas vezes: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.outfit('30000000-0000-0000-0000-000000000004', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'G1', 'main_top', :'G2', 'main_top')), :'O2') as r \gset
select pg_temp.check('dois tops principais: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.outfit('30000000-0000-0000-0000-000000000005', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'G1', 'capa')), :'O2') as r \gset
select pg_temp.check('papel desconhecido: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.outfit('30000000-0000-0000-0000-000000000006', 'create_outfit',
  '{"items":[]}', :'O2') as r \gset
select pg_temp.check('sem peças: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.outfit('30000000-0000-0000-0000-000000000007', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'GB', 'main_top')), :'O2') as r \gset
select pg_temp.check('peça de outra conta: not_found', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.outfit('30000000-0000-0000-0000-000000000008', 'create_outfit',
  jsonb_build_object('occasions', '["praia"]'::jsonb,
    'items', pg_temp.items(:'G1', 'main_top')), :'O2') as r \gset
select pg_temp.check('ocasião desconhecida: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.outfit('30000000-0000-0000-0000-000000000009', 'create_outfit',
  jsonb_build_object('name', '', 'items', pg_temp.items(:'G1', 'main_top')), :'O2') as r \gset
select pg_temp.check('nome vazio: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.check('rejeitadas não criaram nada', (select count(*) = 1 from public.outfits));
commit;

-- ----------------------------------------------------------------- editar
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.outfit('40000000-0000-0000-0000-000000000001', 'edit_outfit',
  '{"occasions":["work_casual"]}') as r \gset
select pg_temp.check('só o campo enviado muda',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select name = 'Sexta' and occasions = '["work_casual"]' and jsonb_array_length(items) = 3
       from public.outfits where id = :'O1'));
select pg_temp.outfit('40000000-0000-0000-0000-000000000002', 'edit_outfit',
  jsonb_build_object('name', null, 'items', pg_temp.items(:'G1', 'main_top', :'G3', 'footwear'))) as r \gset
select pg_temp.check('troca peças e apaga o nome',
  (select name is null and jsonb_array_length(items) = 2 from public.outfits where id = :'O1'));
select pg_temp.outfit('40000000-0000-0000-0000-000000000003', 'edit_outfit',
  jsonb_build_object('items', pg_temp.items(:'GB', 'main_top'))) as r \gset
select pg_temp.check('editar com peça de outra conta: not_found',
  :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.outfit('40000000-0000-0000-0000-000000000004', 'edit_outfit',
  '{"name":"x"}', :'O2') as r \gset
select pg_temp.check('editar desconhecido: not_found', :'r'::jsonb ->> 'reason' = 'not_found');

-- Uma peça eliminada não apaga o conjunto.
select public.apply_garment_operation(jsonb_build_object(
  'op_id', '40000000-0000-0000-0000-000000000005', 'garment_id', :'G3',
  'kind', 'delete', 'data', '{}'::jsonb));
select pg_temp.check('peça eliminada não apaga o conjunto',
  (select deleted_at is null from public.outfits where id = :'O1'));
select pg_temp.outfit('40000000-0000-0000-0000-000000000006', 'edit_outfit',
  '{"name":"Ainda"}') as r \gset
select pg_temp.check('e o nome ainda se edita', :'r'::jsonb ->> 'result' = 'applied');
commit;

-- ---------------------------------------------------------------- eliminar
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.outfit('50000000-0000-0000-0000-000000000001', 'delete_outfit', '{}') as r \gset
select pg_temp.check('outra conta não elimina', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.check('nem vê', (select count(*) = 0 from public.outfits));
select pg_temp.check('nem escreve diretamente',
  not has_table_privilege('authenticated', 'public.outfits', 'insert'));
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.outfit('50000000-0000-0000-0000-000000000002', 'delete_outfit', '{}') as r \gset
select pg_temp.outfit('50000000-0000-0000-0000-000000000003', 'delete_outfit', '{}') as r2 \gset
select pg_temp.check('elimina; repetir é inofensivo',
  :'r'::jsonb ->> 'result' = 'applied' and :'r2'::jsonb ->> 'result' = 'applied'
  and (select deleted_at is not null from public.outfits where id = :'O1'));
select pg_temp.outfit('50000000-0000-0000-0000-000000000004', 'edit_outfit', '{"name":"y"}') as r \gset
select pg_temp.check('eliminado não se edita', :'r'::jsonb ->> 'reason' = 'not_found');
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.outfit('60000000-0000-0000-0000-000000000001', 'create_outfit',
  jsonb_build_object('items', pg_temp.items(:'G1', 'main_top')), :'O2') as r \gset
select pg_temp.check('fora da allowlist: unauthorized', :'r'::jsonb ->> 'reason' = 'unauthorized');
rollback;

\echo 'Testes de conjuntos passaram.'
