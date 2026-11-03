-- Testes de preferências de estilo (apply_style_operation).
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'eu@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
insert into public.allowed_users (email) values ('eu@example.com'), ('outra@example.com');

create function pg_temp.as_user(sub text, email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', sub, 'email', email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.style(op_id text, kind text, data jsonb,
  entity text default 'f0000000-0000-0000-0000-000000000001') returns jsonb
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
\set INS 'e0000000-0000-0000-0000-000000000001'
\set P1 'f0000000-0000-0000-0000-000000000001'
\set P2 'f0000000-0000-0000-0000-000000000002'

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('20000000-0000-0000-0000-000000000001', 'create_inspiration',
  '{"title":"Neutros"}', :'INS');
select pg_temp.style('30000000-0000-0000-0000-000000000001', 'create_preference',
  jsonb_build_object('subject', 'combo', 'value', 'neutral_base', 'stance', 'like',
    'occasions', '["work_casual"]'::jsonb, 'inspiration_id', :'INS')) as r \gset
select pg_temp.check('cria preferência com contexto e origem',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select stance = 'like' and occasions = '["work_casual"]' and inspiration_id = :'INS'
       from public.style_preferences where id = :'P1'));
select pg_temp.style('30000000-0000-0000-0000-000000000001', 'create_preference',
  '{"subject":"color","value":"0","stance":"avoid"}') as r \gset
select pg_temp.check('repetir op_id não duplica',
  :'r'::jsonb ->> 'result' = 'applied' and (select count(*) = 1 from public.style_preferences));
select pg_temp.style('30000000-0000-0000-0000-000000000002', 'create_preference',
  '{"subject":"color","value":"1316116","stance":"avoid"}', :'P2') as r \gset
select pg_temp.check('evitar uma cor, sempre', :'r'::jsonb ->> 'result' = 'applied'
  and (select occasions = '[]' from public.style_preferences where id = :'P2'));
select pg_temp.check('não cria peças', (select count(*) = 0 from public.garments));
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.check('rejeita o inválido', bool_and(
    pg_temp.style(op, 'create_preference', data,
      'f0000000-0000-0000-0000-0000000000ff') ->> 'reason' = reason)
  and (select count(*) = 2 from public.style_preferences))
from (values
  ('31000000-0000-0000-0000-000000000001', '{"subject":"color","value":"azul","stance":"like"}'::jsonb, 'invalid'),
  ('31000000-0000-0000-0000-000000000002', '{"subject":"color","value":"16777216","stance":"like"}', 'invalid'),
  ('31000000-0000-0000-0000-000000000003', '{"subject":"pattern","value":"knit","stance":"like"}', 'invalid'),
  ('31000000-0000-0000-0000-000000000004', '{"subject":"brand","value":"x","stance":"like"}', 'invalid'),
  ('31000000-0000-0000-0000-000000000005', '{"subject":"texture","value":"knit","stance":"love"}', 'invalid'),
  ('31000000-0000-0000-0000-000000000006', '{"subject":"texture","value":"knit"}', 'invalid'),
  ('31000000-0000-0000-0000-000000000007', '{"subject":"formality","value":"dressy","stance":"like","occasions":["praia"]}', 'invalid'),
  ('31000000-0000-0000-0000-000000000008', '{"subject":"formality","value":"dressy","stance":"like","inspiration_id":"e0000000-0000-0000-0000-0000000000ee"}', 'not_found')
) as t(op, data, reason);
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('40000000-0000-0000-0000-000000000001', 'edit_preference',
  '{"stance":"avoid","occasions":[]}') as r \gset
select pg_temp.check('editar muda só os campos enviados',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select stance = 'avoid' and occasions = '[]' and value = 'neutral_base'
       from public.style_preferences where id = :'P1'));
select pg_temp.style('40000000-0000-0000-0000-000000000002', 'edit_preference',
  '{"subject":"color"}') as r \gset
select pg_temp.check('o assunto não muda', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.style('40000000-0000-0000-0000-000000000003', 'edit_preference',
  '{"value":"stripes"}') as r \gset
select pg_temp.check('valor tem de servir o assunto', :'r'::jsonb ->> 'reason' = 'invalid'
  and (select value = 'neutral_base' from public.style_preferences where id = :'P1'));

select pg_temp.style('40000000-0000-0000-0000-000000000004', 'delete_inspiration', '{}', :'INS');
select pg_temp.check('eliminar a inspiração mantém a preferência',
  (select deleted_at is null from public.style_preferences where id = :'P1'));
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.style('50000000-0000-0000-0000-000000000001', 'delete_preference', '{}') as r \gset
select pg_temp.check('outra conta não elimina', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.check('nem vê', (select count(*) = 0 from public.style_preferences));
select pg_temp.style('50000000-0000-0000-0000-000000000002', 'create_preference',
  jsonb_build_object('subject', 'combo', 'value', 'tonal', 'stance', 'like',
    'inspiration_id', :'INS'), 'f0000000-0000-0000-0000-0000000000b1') as r \gset
select pg_temp.check('nem usa a inspiração de outra conta como origem',
  :'r'::jsonb ->> 'reason' = 'not_found');
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.style('60000000-0000-0000-0000-000000000001', 'delete_preference', '{}') as r \gset
select pg_temp.style('60000000-0000-0000-0000-000000000002', 'delete_preference', '{}') as r2 \gset
select pg_temp.check('elimina; repetir é inofensivo',
  :'r'::jsonb ->> 'result' = 'applied' and :'r2'::jsonb ->> 'result' = 'applied'
  and (select deleted_at is not null from public.style_preferences where id = :'P1'));
select pg_temp.style('60000000-0000-0000-0000-000000000003', 'edit_preference',
  '{"stance":"like"}') as r \gset
select pg_temp.check('eliminada não se edita', :'r'::jsonb ->> 'reason' = 'not_found');
commit;

\echo 'Testes de preferências passaram.'
