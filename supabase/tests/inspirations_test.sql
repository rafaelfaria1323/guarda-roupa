-- Testes de inspirações (apply_style_operation).
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
\set I2 'e0000000-0000-0000-0000-000000000002'

-- ------------------------------------------------------------------ criar
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('30000000-0000-0000-0000-000000000001', 'create_inspiration',
  '{"title":"Neutros com acento","source_url":"https://www.pinterest.com/pin/123/",
    "palette":[16777215,1316116,12597547],"formality":"smart_casual",
    "patterns":["plain"],"textures":["knit","smooth"],"occasions":["work_casual"]}') as r \gset
select pg_temp.check('cria inspiração com link e etiquetas',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select title = 'Neutros com acento' and jsonb_array_length(palette) = 3
         and formality = 'smart_casual' and owner_id = auth.uid()
       from public.inspirations where id = :'I1'));
select pg_temp.check('não cria peças', (select count(*) = 0 from public.garments));
select pg_temp.style('30000000-0000-0000-0000-000000000001', 'create_inspiration',
  '{"title":"Outra"}') as r \gset
select pg_temp.check('repetir op_id devolve o mesmo e não duplica',
  :'r'::jsonb ->> 'result' = 'applied' and (select count(*) = 1 from public.inspirations));
select pg_temp.style('30000000-0000-0000-0000-000000000002', 'create_inspiration',
  '{"title":"Outra"}') as r \gset
select pg_temp.check('mesmo id: already_exists', :'r'::jsonb ->> 'reason' = 'already_exists');

select pg_temp.style('30000000-0000-0000-0000-000000000003', 'create_inspiration',
  '{"source_url":"https://example.com/look"}', :'I2') as r \gset
select pg_temp.check('só link (sem imagem nem título) é válido',
  :'r'::jsonb ->> 'result' = 'applied');
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.check('rejeita o inválido', bool_and(
    pg_temp.style(op, 'create_inspiration', data,
      'e0000000-0000-0000-0000-0000000000ff') ->> 'reason' = 'invalid')
  and (select count(*) = 2 from public.inspirations))
from (values
  ('31000000-0000-0000-0000-000000000001', '{}'::jsonb),
  ('31000000-0000-0000-0000-000000000002', '{"source_url":"javascript:alert(1)"}'),
  ('31000000-0000-0000-0000-000000000003', '{"source_url":"https://a b.com"}'),
  ('31000000-0000-0000-0000-000000000004', '{"title":""}'),
  ('31000000-0000-0000-0000-000000000005', '{"title":"x","palette":[1,1]}'),
  ('31000000-0000-0000-0000-000000000006', '{"title":"x","palette":[16777216]}'),
  ('31000000-0000-0000-0000-000000000007', '{"title":"x","formality":"black_tie"}'),
  ('31000000-0000-0000-0000-000000000008', '{"title":"x","patterns":["plain","plain"]}'),
  ('31000000-0000-0000-0000-000000000009', '{"title":"x","textures":["seda"]}'),
  ('31000000-0000-0000-0000-00000000000a', '{"title":"x","occasions":["praia"]}'),
  ('31000000-0000-0000-0000-00000000000b', '{"title":"x","notes":""}')
) as t(op, data);
commit;

-- ----------------------------------------------------------------- editar
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('40000000-0000-0000-0000-000000000001', 'edit_inspiration',
  '{"formality":null,"textures":["ribbed"]}') as r \gset
select pg_temp.check('só os campos enviados mudam; null apaga',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select formality is null and textures = '["ribbed"]' and patterns = '["plain"]'
         and title = 'Neutros com acento' from public.inspirations where id = :'I1'));
select pg_temp.style('40000000-0000-0000-0000-000000000002', 'edit_inspiration',
  '{"source_url":null}', :'I2') as r \gset
select pg_temp.check('não fica sem título nem link',
  :'r'::jsonb ->> 'reason' = 'invalid'
  and (select source_url is not null from public.inspirations where id = :'I2'));
select pg_temp.style('40000000-0000-0000-0000-000000000003', 'edit_inspiration',
  '{"title":"x"}', 'e0000000-0000-0000-0000-0000000000ee') as r \gset
select pg_temp.check('editar desconhecida: not_found', :'r'::jsonb ->> 'reason' = 'not_found');
commit;

-- ---------------------------------------------------------------- eliminar
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.style('50000000-0000-0000-0000-000000000001', 'delete_inspiration', '{}') as r \gset
select pg_temp.check('outra conta não elimina', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.check('nem vê', (select count(*) = 0 from public.inspirations));
select pg_temp.check('nem escreve diretamente',
  not has_table_privilege('authenticated', 'public.inspirations', 'insert'));
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('50000000-0000-0000-0000-000000000002', 'delete_inspiration', '{}') as r \gset
select pg_temp.style('50000000-0000-0000-0000-000000000003', 'delete_inspiration', '{}') as r2 \gset
select pg_temp.check('elimina; repetir é inofensivo',
  :'r'::jsonb ->> 'result' = 'applied' and :'r2'::jsonb ->> 'result' = 'applied'
  and (select deleted_at is not null from public.inspirations where id = :'I1'));
select pg_temp.style('50000000-0000-0000-0000-000000000004', 'edit_inspiration',
  '{"title":"y"}') as r \gset
select pg_temp.check('eliminada não se edita', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.style('50000000-0000-0000-0000-000000000005', 'apagar_tudo', '{}') as r \gset
select pg_temp.check('tipo desconhecido: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.style('60000000-0000-0000-0000-000000000001', 'create_inspiration',
  '{"title":"x"}', :'I2') as r \gset
select pg_temp.check('fora da allowlist: unauthorized', :'r'::jsonb ->> 'reason' = 'unauthorized');
rollback;

\echo 'Testes de inspirações passaram.'
