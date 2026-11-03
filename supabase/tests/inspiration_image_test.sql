-- Testes da imagem e das proporções das inspirações.
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

create function pg_temp.style(op_id text, kind text, data jsonb,
  entity text default 'e0000000-0000-0000-0000-000000000001') returns jsonb
language sql as $$
  select public.apply_style_operation(jsonb_build_object(
    'op_id', op_id, 'entity_id', entity, 'kind', kind, 'data', data));
$$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

\set A '00000000-0000-0000-0000-00000000000a'
\set I1 'e0000000-0000-0000-0000-000000000001'
\set A '00000000-0000-0000-0000-00000000000a'
\set I1 'e0000000-0000-0000-0000-000000000001'
\set P1 'f0000000-0000-0000-0000-000000000001'
\set P2 'f0000000-0000-0000-0000-000000000002'

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('40000000-0000-0000-0000-000000000001', 'create_inspiration',
  '{"title":"Largo em cima","proportions":["relaxed_top_fitted_bottom","long_layer"]}') as r \gset
select pg_temp.check('cria com proporções',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select proportions = '["relaxed_top_fitted_bottom","long_layer"]'::jsonb
       and image is null from public.inspirations where id = :'I1'));

select pg_temp.check('proporções inválidas são rejeitadas', bool_and(
    pg_temp.style(op, kind, data) ->> 'reason' = 'invalid'))
from (values
  ('41000000-0000-0000-0000-000000000001', 'edit_inspiration', '{"proportions":["oversized"]}'::jsonb),
  ('41000000-0000-0000-0000-000000000002', 'edit_inspiration', '{"proportions":["all_fitted","all_fitted"]}'),
  ('41000000-0000-0000-0000-000000000003', 'edit_inspiration', '{"proportions":"all_fitted"}')
) as t(op, kind, data);

select pg_temp.style('40000000-0000-0000-0000-000000000002', 'edit_inspiration',
  '{"proportions":[]}') as r \gset
select pg_temp.check('editar limpa as proporções',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select proportions = '[]'::jsonb from public.inspirations where id = :'I1'));

-- ------------------------------------------------------------------ imagem
select jsonb_build_object('image', jsonb_build_object(
  'id', :'P1', 'width', 1200, 'height', 1600, 'bytes', 250000,
  'thumb_bytes', 12000, 'sha256', repeat('ab', 32))) as img1 \gset
select jsonb_build_object('image', jsonb_build_object(
  'id', :'P2', 'width', 800, 'height', 800, 'bytes', 90000,
  'thumb_bytes', 9000, 'sha256', repeat('cd', 32))) as img2 \gset

select pg_temp.style('42000000-0000-0000-0000-000000000001', 'set_inspiration_image', :'img1') as r \gset
select pg_temp.check('sem ficheiros: missing_file', :'r'::jsonb ->> 'reason' = 'missing_file');
insert into storage.objects (bucket_id, name) values
  ('garment-photos', :'A' || '/' || :'P1' || '/main.jpg');
select pg_temp.style('42000000-0000-0000-0000-000000000002', 'set_inspiration_image', :'img1') as r \gset
select pg_temp.check('só a principal: missing_file', :'r'::jsonb ->> 'reason' = 'missing_file');
insert into storage.objects (bucket_id, name) values
  ('garment-photos', :'A' || '/' || :'P1' || '/thumb.jpg');
select pg_temp.style('42000000-0000-0000-0000-000000000003', 'set_inspiration_image', :'img1') as r \gset
select pg_temp.check('com os dois ficheiros liga a imagem',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select image ->> 'id' = :'P1' and (image ->> 'width')::int = 1200
       from public.inspirations where id = :'I1'));
select pg_temp.style('42000000-0000-0000-0000-000000000004', 'set_inspiration_image', :'img1') as r \gset
select pg_temp.check('a mesma imagem (outro op_id) é aplicada sem mudar nada',
  :'r'::jsonb ->> 'result' = 'applied');

select pg_temp.check('imagens inválidas são rejeitadas', bool_and(
    pg_temp.style(op, 'set_inspiration_image', data) ->> 'reason' = 'invalid'))
from (values
  ('43000000-0000-0000-0000-000000000001', '{}'::jsonb),
  ('43000000-0000-0000-0000-000000000002', '{"image":{"id":"x"}}'),
  ('43000000-0000-0000-0000-000000000003', jsonb_set(:'img2'::jsonb, '{image,width}', '0')),
  ('43000000-0000-0000-0000-000000000004', jsonb_set(:'img2'::jsonb, '{image,sha256}', '"zz"'))
) as t(op, data);

select pg_temp.check('inspiração inexistente: not_found',
  pg_temp.style('44000000-0000-0000-0000-000000000001', 'set_inspiration_image', :'img1',
    'e0000000-0000-0000-0000-0000000000ee') ->> 'reason' = 'not_found');

-- Trocar: retirar a antiga e ligar a nova.
insert into storage.objects (bucket_id, name) values
  ('garment-photos', :'A' || '/' || :'P2' || '/main.jpg'),
  ('garment-photos', :'A' || '/' || :'P2' || '/thumb.jpg');
select pg_temp.style('45000000-0000-0000-0000-000000000001', 'remove_inspiration_image',
  jsonb_build_object('photo_id', :'P1')) as r \gset
select pg_temp.check('retirar a imagem atual',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select image is null from public.inspirations where id = :'I1'));
select pg_temp.style('45000000-0000-0000-0000-000000000002', 'set_inspiration_image', :'img2') as r \gset
select pg_temp.check('ligar a nova', :'r'::jsonb ->> 'result' = 'applied'
  and (select image ->> 'id' = :'P2' from public.inspirations where id = :'I1'));
select pg_temp.style('45000000-0000-0000-0000-000000000003', 'remove_inspiration_image',
  jsonb_build_object('photo_id', :'P1')) as r \gset
select pg_temp.check('retirar uma imagem antiga não apaga a atual',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select image ->> 'id' = :'P2' from public.inspirations where id = :'I1'));

select pg_temp.style('46000000-0000-0000-0000-000000000001', 'delete_inspiration', '{}') as r \gset
select pg_temp.check('eliminada: ligar imagem dá not_found',
  pg_temp.style('46000000-0000-0000-0000-000000000002', 'set_inspiration_image', :'img1')
    ->> 'reason' = 'not_found');
commit;

\echo 'Testes da imagem das inspirações passaram.'
