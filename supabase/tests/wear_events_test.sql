-- Testes de apply_wear_operation (utilizações reais, P-08).
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

create function pg_temp.wear(op_id text, kind text, data jsonb,
  event text default 'e0000000-0000-0000-0000-000000000001') returns jsonb
language sql as $$
  select public.apply_wear_operation(jsonb_build_object(
    'op_id', op_id, 'event_id', event, 'kind', kind, 'data', data));
$$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

\set G1 '10000000-0000-0000-0000-000000000001'
\set G2 '10000000-0000-0000-0000-000000000002'
\set GB '10000000-0000-0000-0000-0000000000b1'
\set E1 'e0000000-0000-0000-0000-000000000001'
\set E2 'e0000000-0000-0000-0000-000000000002'
\set E3 'e0000000-0000-0000-0000-000000000003'
\set P1 'f0000000-0000-0000-0000-000000000001'

-- Peças: duas da conta a, uma da conta b.
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.garment('20000000-0000-0000-0000-000000000001', :'G1');
select pg_temp.garment('20000000-0000-0000-0000-000000000002', :'G2');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.garment('20000000-0000-0000-0000-000000000003', :'GB');
commit;

-- -------------------------------------------------------------- allowlist
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.wear('30000000-0000-0000-0000-000000000001', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'G1'))) as r \gset
select pg_temp.check('conta fora da allowlist é rejeitada', :'r'::jsonb ->> 'reason' = 'unauthorized');
rollback;

-- ---------------------------------------------------------------- registo
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');

select pg_temp.wear('40000000-0000-0000-0000-000000000001', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'G1', :'G2'),
    'plan_entry_id', :'P1')) as r \gset
select pg_temp.check('regista utilização', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('com dono, data e peças',
  (select owner_id = auth.uid() and worn_on = '2026-11-03' and jsonb_array_length(garment_ids) = 2
   from public.wear_events where id = :'E1'));

select pg_temp.wear('40000000-0000-0000-0000-000000000001', 'record_wear',
  jsonb_build_object('worn_on', '2026-01-01', 'garment_ids', jsonb_build_array(:'G2'))) as r \gset
select pg_temp.check('repetir o op_id devolve o resultado original', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('e não duplica nem altera',
  (select count(*) = 1 and bool_and(worn_on = '2026-11-03') from public.wear_events));

select pg_temp.wear('40000000-0000-0000-0000-000000000002', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'G1'))) as r \gset
select pg_temp.check('mesmo id de evento com outro op: already_exists',
  :'r'::jsonb ->> 'reason' = 'already_exists');

select pg_temp.wear('40000000-0000-0000-0000-000000000003', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'G1'),
    'plan_entry_id', :'P1'), :'E2') as r \gset
select pg_temp.check('mesma entrada de plano noutro dispositivo: merged',
  :'r'::jsonb ->> 'result' = 'merged' and :'r'::jsonb ->> 'reason' = 'plan_already_confirmed');
select pg_temp.check('e conta uma só utilização', (select count(*) = 1 from public.wear_events));

select pg_temp.wear('40000000-0000-0000-0000-000000000004', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'GB')), :'E3') as r \gset
select pg_temp.check('peça de outra conta: not_found', :'r'::jsonb ->> 'reason' = 'not_found');

select pg_temp.wear('40000000-0000-0000-0000-000000000005', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03',
    'garment_ids', jsonb_build_array('10000000-0000-0000-0000-000000000999')), :'E3') as r \gset
select pg_temp.check('peça inexistente: not_found', :'r'::jsonb ->> 'reason' = 'not_found');

select pg_temp.wear('40000000-0000-0000-0000-000000000006', 'record_wear',
  jsonb_build_object('worn_on', '2026-02-30', 'garment_ids', jsonb_build_array(:'G1')), :'E3') as r \gset
select pg_temp.check('data impossível: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('40000000-0000-0000-0000-000000000007', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'G1', :'G1')), :'E3') as r \gset
select pg_temp.check('peça repetida: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('40000000-0000-0000-0000-000000000008', 'record_wear',
  '{"worn_on":"2026-11-03","garment_ids":[]}', :'E3') as r \gset
select pg_temp.check('sem peças: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('40000000-0000-0000-0000-000000000009', 'record_wear',
  '{"worn_on":"2026-11-03","garment_ids":["abc"]}', :'E3') as r \gset
select pg_temp.check('id que não é uuid: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('40000000-0000-0000-0000-000000000010', 'dance', '{}', :'E3') as r \gset
select pg_temp.check('tipo desconhecido: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.check('nenhuma das rejeitadas criou eventos', (select count(*) = 1 from public.wear_events));
commit;

-- ------------------------------------------------------------- RLS / leitura
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.check('outra conta não vê os eventos', (select count(*) = 0 from public.wear_events));
select pg_temp.wear('50000000-0000-0000-0000-000000000001', 'void_wear', '{}') as r \gset
select pg_temp.check('nem os desfaz', :'r'::jsonb ->> 'reason' = 'not_found');
rollback;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.check('escrita direta é recusada', (
  select not has_table_privilege('authenticated', 'public.wear_events', 'insert')
     and not has_table_privilege('authenticated', 'public.wear_events', 'update')));
rollback;

-- ----------------------------------------------------------------- desfazer
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.wear('60000000-0000-0000-0000-000000000001', 'void_wear', '{}') as r \gset
select pg_temp.check('desfaz', :'r'::jsonb ->> 'result' = 'applied'
  and (select voided_at is not null from public.wear_events where id = :'E1'));
select voided_at as v1 from public.wear_events where id = :'E1' \gset
select pg_temp.wear('60000000-0000-0000-0000-000000000002', 'void_wear', '{}') as r \gset
select pg_temp.check('desfazer de novo é inofensivo', :'r'::jsonb ->> 'result' = 'applied'
  and (select voided_at = :'v1'::timestamptz from public.wear_events where id = :'E1'));
select pg_temp.wear('60000000-0000-0000-0000-000000000003', 'void_wear', '{}', :'E3') as r \gset
select pg_temp.check('desfazer evento desconhecido: not_found', :'r'::jsonb ->> 'reason' = 'not_found');

select pg_temp.wear('60000000-0000-0000-0000-000000000004', 'record_wear',
  jsonb_build_object('worn_on', '2026-11-03', 'garment_ids', jsonb_build_array(:'G1'),
    'plan_entry_id', :'P1'), :'E2') as r \gset
select pg_temp.check('depois de desfazer, a entrada de plano pode ser confirmada outra vez',
  :'r'::jsonb ->> 'result' = 'applied');
commit;

\echo 'Testes de utilizações passaram.'
