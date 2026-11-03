-- Testes de limpezas e políticas (apply_wear_operation, P-06/P-07).
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
\set C1 'c0000000-0000-0000-0000-000000000001'
\set C2 'c0000000-0000-0000-0000-000000000002'
\set A '00000000-0000-0000-0000-00000000000a'

-- ----------------------------------------------------------------- limpezas
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.wear('70000000-0000-0000-0000-000000000001', 'record_cleaning',
  jsonb_build_object('garment_id', :'G1', 'cleaned_on', '2026-11-02'), :'C1') as r \gset
select pg_temp.check('regista limpeza', :'r'::jsonb ->> 'result' = 'applied'
  and (select cleaned_on = '2026-11-02' and garment_id = :'G1' and owner_id = auth.uid()
       from public.cleaning_events where id = :'C1'));
select pg_temp.wear('70000000-0000-0000-0000-000000000001', 'record_cleaning',
  jsonb_build_object('garment_id', :'G2', 'cleaned_on', '2026-01-01'), :'C1') as r \gset
select pg_temp.check('repetir op_id não duplica', (select count(*) = 1 from public.cleaning_events));
select pg_temp.wear('70000000-0000-0000-0000-000000000002', 'record_cleaning',
  jsonb_build_object('garment_id', :'G1', 'cleaned_on', '2026-11-02'), :'C1') as r \gset
select pg_temp.check('mesmo id: already_exists', :'r'::jsonb ->> 'reason' = 'already_exists');
select pg_temp.wear('70000000-0000-0000-0000-000000000003', 'record_cleaning',
  jsonb_build_object('garment_id', :'GB', 'cleaned_on', '2026-11-02'), :'C2') as r \gset
select pg_temp.check('peça de outra conta: not_found', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.wear('70000000-0000-0000-0000-000000000004', 'record_cleaning',
  jsonb_build_object('garment_id', :'G1', 'cleaned_on', 'ontem'), :'C2') as r \gset
select pg_temp.check('data inválida: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('70000000-0000-0000-0000-000000000005', 'record_cleaning',
  '{"cleaned_on":"2026-11-02"}', :'C2') as r \gset
select pg_temp.check('sem peça: invalid', :'r'::jsonb ->> 'reason' = 'invalid');

select pg_temp.wear('70000000-0000-0000-0000-000000000006', 'void_cleaning', '{}', :'C1') as r \gset
select pg_temp.check('desfaz limpeza', :'r'::jsonb ->> 'result' = 'applied'
  and (select voided_at is not null from public.cleaning_events where id = :'C1'));
select pg_temp.wear('70000000-0000-0000-0000-000000000007', 'void_cleaning', '{}', :'C2') as r \gset
select pg_temp.check('desfazer desconhecida: not_found', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.wear('70000000-0000-0000-0000-000000000008', 'void_wear', '{}', :'C1') as r \gset
select pg_temp.check('void_wear não toca em limpezas', :'r'::jsonb ->> 'reason' = 'not_found');
commit;

-- ---------------------------------------------------------------- políticas
select md5(:'A' || ':category:t_shirt')::uuid as pcat \gset
select md5(:'A' || ':garment:' || :'G1')::uuid as pg1 \gset
select md5(:'A' || ':garment:' || :'GB')::uuid as pgb \gset

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.wear('80000000-0000-0000-0000-000000000001', 'set_policy',
  '{"scope":"category","target":"t_shirt","laundry_after":2}', :'pcat') as r \gset
select pg_temp.check('define política da categoria', :'r'::jsonb ->> 'result' = 'applied'
  and (select laundry_after = 2 and rotation_days is null from public.care_policies where id = :'pcat'));
select pg_temp.wear('80000000-0000-0000-0000-000000000002', 'set_policy',
  '{"scope":"category","target":"t_shirt","rotation_days":5}', :'pcat') as r \gset
select pg_temp.check('só o campo enviado muda',
  (select laundry_after = 2 and rotation_days = 5 from public.care_policies where id = :'pcat'));
select pg_temp.wear('80000000-0000-0000-0000-000000000003', 'set_policy',
  '{"scope":"category","target":"t_shirt","laundry_after":null}', :'pcat') as r \gset
select pg_temp.check('null volta ao predefinido, uma só linha',
  (select count(*) = 1 and bool_and(laundry_after is null and rotation_days = 5)
   from public.care_policies));

select pg_temp.wear('80000000-0000-0000-0000-000000000004', 'set_policy',
  jsonb_build_object('scope', 'garment', 'target', :'G1', 'laundry_after', 0), :'pg1') as r \gset
select pg_temp.check('define política da peça (0 = sem aviso)', :'r'::jsonb ->> 'result' = 'applied'
  and (select laundry_after = 0 from public.care_policies where id = :'pg1'));
select pg_temp.wear('80000000-0000-0000-0000-000000000005', 'set_policy',
  jsonb_build_object('scope', 'garment', 'target', :'GB', 'laundry_after', 1), :'pgb') as r \gset
select pg_temp.check('peça de outra conta: not_found', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.wear('80000000-0000-0000-0000-000000000006', 'set_policy',
  '{"scope":"category","target":"t_shirt","laundry_after":1}', :'pg1') as r \gset
select pg_temp.check('id que não corresponde ao alvo: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('80000000-0000-0000-0000-000000000007', 'set_policy',
  '{"scope":"category","target":"t_shirt","laundry_after":99}', :'pcat') as r \gset
select pg_temp.check('valor fora dos limites: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.wear('80000000-0000-0000-0000-000000000008', 'set_policy',
  '{"scope":"category","target":"t_shirt"}', :'pcat') as r \gset
select pg_temp.check('sem campos: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.check('rejeitadas não mudaram nada',
  (select count(*) = 2 from public.care_policies));
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.check('outra conta não vê limpezas nem políticas',
  (select count(*) = 0 from public.cleaning_events)
  and (select count(*) = 0 from public.care_policies));
select pg_temp.check('nem escreve diretamente',
  not has_table_privilege('authenticated', 'public.care_policies', 'insert'));
rollback;

\echo 'Testes de lavandaria passaram.'
