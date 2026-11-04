-- Testes do plano semanal (apply_plan_operation).
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

create function pg_temp.plan(op_id text, kind text, data jsonb,
  entry text default 'e0000000-0000-0000-0000-000000000001') returns jsonb
language sql as $$
  select public.apply_plan_operation(jsonb_build_object(
    'op_id', op_id, 'entry_id', entry, 'kind', kind, 'data', data));
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
\set GB '10000000-0000-0000-0000-0000000000b1'
\set E1 'e0000000-0000-0000-0000-000000000001'
\set E2 'e0000000-0000-0000-0000-000000000002'
\set E3 'e0000000-0000-0000-0000-000000000003'

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.garment('20000000-0000-0000-0000-000000000001', :'G1');
select pg_temp.garment('20000000-0000-0000-0000-000000000002', :'G2');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.garment('20000000-0000-0000-0000-000000000004', :'GB');
commit;

-- ------------------------------------------------------------------ criar
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.plan('30000000-0000-0000-0000-000000000001', 'create_plan_entry',
  jsonb_build_object('day', '2026-11-09', 'occasion', 'work_casual',
    'items', pg_temp.items(:'G1', 'main_top', :'G2', 'bottom'))) as r \gset
select pg_temp.check('cria segunda-feira de trabalho',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select day = '2026-11-09' and occasion = 'work_casual' and not tentative
         and status = 'proposed' and version = 1 and jsonb_array_length(items) = 2
         and proposal is null and owner_id = auth.uid()
       from public.plan_entries where id = :'E1'));
select pg_temp.plan('30000000-0000-0000-0000-000000000001', 'create_plan_entry',
  '{"day":"2026-11-10"}') as r \gset
select pg_temp.check('repetir op_id devolve o mesmo e não duplica',
  :'r'::jsonb ->> 'result' = 'applied' and (select count(*) = 1 from public.plan_entries));
select pg_temp.plan('30000000-0000-0000-0000-000000000002', 'create_plan_entry',
  '{"day":"2026-11-14","tentative":true,"occasion":null}', :'E2') as r \gset
select pg_temp.check('sábado a decidir, provisório e vazio',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select occasion is null and tentative and items = '[]'
       from public.plan_entries where id = :'E2'));

select pg_temp.plan('30000000-0000-0000-0000-000000000003', 'create_plan_entry',
  '{"day":"2026-02-30"}', :'E3') as r \gset
select pg_temp.check('data impossível: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.plan('30000000-0000-0000-0000-000000000004', 'create_plan_entry',
  '{"day":"2026-11-11","occasion":"praia"}', :'E3') as r \gset
select pg_temp.check('ocasião desconhecida: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.plan('30000000-0000-0000-0000-000000000005', 'create_plan_entry',
  jsonb_build_object('day', '2026-11-11',
    'items', pg_temp.items(:'G1', 'main_top', :'G2', 'main_top')), :'E3') as r \gset
select pg_temp.check('dois tops principais: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.plan('30000000-0000-0000-0000-000000000006', 'create_plan_entry',
  jsonb_build_object('day', '2026-11-11', 'items', pg_temp.items(:'GB', 'main_top')),
  :'E3') as r \gset
select pg_temp.check('peça de outra conta: not_found', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.plan('30000000-0000-0000-0000-000000000007', 'create_plan_entry',
  '{"day":"2026-11-11","status":"worn"}', :'E3') as r \gset
select pg_temp.check('estado desconhecido: invalid', :'r'::jsonb ->> 'reason' = 'invalid');

-- Outro dispositivo, offline, criou a mesma segunda-feira com outro id.
select pg_temp.plan('30000000-0000-0000-0000-000000000008', 'create_plan_entry',
  jsonb_build_object('day', '2026-11-09', 'occasion', 'casual'), :'E3') as r \gset
select pg_temp.check('dia ocupado: proposta na entrada existente',
  :'r'::jsonb ->> 'result' = 'conflict' and :'r'::jsonb ->> 'reason' = 'day_taken'
  and :'r'::jsonb ->> 'entry_id' = :'E1'
  and (select occasion = 'work_casual' and proposal = '{"occasion":"casual"}'
       from public.plan_entries where id = :'E1')
  and (select count(*) = 2 from public.plan_entries));
commit;

-- ----------------------------------------------------------------- editar
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.plan('40000000-0000-0000-0000-000000000001', 'edit_plan_entry',
  '{"base_version":1,"status":"accepted"}') as r \gset
select pg_temp.check('aceitar com a versão certa aplica e sobe a versão',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select status = 'accepted' and version = 2 and occasion = 'work_casual'
         and jsonb_array_length(items) = 2
       from public.plan_entries where id = :'E1'));
select pg_temp.plan('40000000-0000-0000-0000-000000000002', 'edit_plan_entry',
  jsonb_build_object('base_version', 1, 'items', pg_temp.items(:'G1', 'main_top'))) as r \gset
select pg_temp.check('versão desatualizada: fica como proposta, não se aplica',
  :'r'::jsonb ->> 'result' = 'conflict' and :'r'::jsonb ->> 'reason' = 'stale'
  and (select jsonb_array_length(items) = 2 and version = 2
         and jsonb_array_length(proposal -> 'items') = 1
       from public.plan_entries where id = :'E1'));
select pg_temp.plan('40000000-0000-0000-0000-000000000003', 'edit_plan_entry',
  '{"status":"accepted"}') as r \gset
select pg_temp.check('sem base_version: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.plan('40000000-0000-0000-0000-000000000004', 'edit_plan_entry',
  '{"base_version":2}') as r \gset
select pg_temp.check('sem alterações: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.plan('40000000-0000-0000-0000-000000000005', 'edit_plan_entry',
  '{"base_version":2,"tentative":"sim"}') as r \gset
select pg_temp.check('provisório não booleano: invalid', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.plan('40000000-0000-0000-0000-000000000006', 'edit_plan_entry',
  '{"base_version":1,"occasion":"casual"}', :'E3') as r \gset
select pg_temp.check('editar desconhecida: not_found', :'r'::jsonb ->> 'reason' = 'not_found');

-- Resolver a proposta.
select pg_temp.plan('40000000-0000-0000-0000-000000000007', 'resolve_plan_proposal',
  '{"accept":true}') as r \gset
select pg_temp.check('aceitar a proposta aplica-a',
  :'r'::jsonb ->> 'result' = 'applied'
  and (select jsonb_array_length(items) = 1 and version = 3 and proposal is null
         and status = 'accepted'
       from public.plan_entries where id = :'E1'));
select pg_temp.plan('40000000-0000-0000-0000-000000000008', 'resolve_plan_proposal',
  '{"accept":false}') as r \gset
select pg_temp.check('resolver sem proposta é inofensivo', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.plan('40000000-0000-0000-0000-000000000009', 'edit_plan_entry',
  '{"base_version":2,"occasion":"evening"}') as r \gset
select pg_temp.plan('40000000-0000-0000-0000-000000000010', 'resolve_plan_proposal',
  '{"accept":false}') as r \gset
select pg_temp.check('rejeitar descarta sem mudar o plano',
  (select occasion = 'work_casual' and proposal is null and version = 3
       from public.plan_entries where id = :'E1'));
select pg_temp.plan('40000000-0000-0000-0000-000000000011', 'edit_plan_entry',
  '{"base_version":3,"occasion":null}') as r \gset
select pg_temp.check('a ocasião pode voltar a "a decidir"',
  (select occasion is null and version = 4 from public.plan_entries where id = :'E1'));
commit;

-- ---------------------------------------------------- uma utilização por entrada
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select public.apply_wear_operation(jsonb_build_object(
  'op_id', '45000000-0000-0000-0000-000000000001',
  'event_id', 'f0000000-0000-0000-0000-000000000001', 'kind', 'record_wear',
  'data', jsonb_build_object('worn_on', '2026-11-09',
    'garment_ids', jsonb_build_array(:'G1'), 'plan_entry_id', :'E1')));
select pg_temp.check('o plano só conta como uso depois de "Vesti hoje"',
  (select count(*) = 1 from public.wear_events where plan_entry_id = :'E1'));
commit;

-- ---------------------------------------------------------------- eliminar
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.plan('50000000-0000-0000-0000-000000000001', 'delete_plan_entry', '{}') as r \gset
select pg_temp.check('outra conta não elimina', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.check('nem vê', (select count(*) = 0 from public.plan_entries));
select pg_temp.check('nem escreve diretamente',
  not has_table_privilege('authenticated', 'public.plan_entries', 'insert'));
commit;

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select pg_temp.plan('50000000-0000-0000-0000-000000000002', 'delete_plan_entry', '{}') as r \gset
select pg_temp.plan('50000000-0000-0000-0000-000000000003', 'delete_plan_entry', '{}') as r2 \gset
select pg_temp.check('elimina; repetir é inofensivo',
  :'r'::jsonb ->> 'result' = 'applied' and :'r2'::jsonb ->> 'result' = 'applied'
  and (select deleted_at is not null from public.plan_entries where id = :'E1'));
select pg_temp.plan('50000000-0000-0000-0000-000000000004', 'edit_plan_entry',
  '{"base_version":4,"status":"accepted"}') as r \gset
select pg_temp.check('eliminada não se edita', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.plan('50000000-0000-0000-0000-000000000005', 'create_plan_entry',
  '{"day":"2026-11-09"}', :'E3') as r \gset
select pg_temp.check('eliminar liberta o dia', :'r'::jsonb ->> 'result' = 'applied');
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.plan('60000000-0000-0000-0000-000000000001', 'create_plan_entry',
  '{"day":"2026-11-12"}', :'E2') as r \gset
select pg_temp.check('fora da allowlist: unauthorized', :'r'::jsonb ->> 'reason' = 'unauthorized');
rollback;

\echo 'Testes do plano passaram.'
