-- Testes da caixa "Por importar" (atalho do iPhone).
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000e1', 'Dono@example.com'),
  ('00000000-0000-0000-0000-0000000000e2', 'outro@example.com'),
  ('00000000-0000-0000-0000-0000000000e3', 'fora@example.com');
insert into public.allowed_users (email) values ('dono@example.com'), ('outro@example.com');

create function pg_temp.as_user(sub text, email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', sub, 'email', email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

create table pg_temp.k (who text primary key, key text);
grant all on pg_temp.k to anon, authenticated;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1', 'dono@example.com');
select pg_temp.check('sem chave: inativo',
  not (public.import_inbox_key_status() ->> 'active')::boolean);
insert into pg_temp.k values ('velha', public.create_import_inbox_key());
insert into pg_temp.k values ('dono', public.create_import_inbox_key());
select pg_temp.check('chave com prefixo e 64 hex',
  (select key ~ '^fio_[0-9a-f]{64}$' from pg_temp.k where who = 'dono'));
select pg_temp.check('chave ativa',
  (public.import_inbox_key_status() ->> 'active')::boolean);
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2', 'outro@example.com');
insert into pg_temp.k values ('outro', public.create_import_inbox_key());
commit;

begin;
select pg_temp.check('só o hash é guardado',
  not exists (select 1 from public.import_inbox_keys ik join pg_temp.k t on ik.key_hash = t.key));
select pg_temp.as_anon();
select pg_temp.check('chave antiga deixa de servir',
  public.submit_import_inbox((select key from pg_temp.k where who = 'velha'),
    'https://www.zara.com/p1', '{"result":"ok"}') = 'invalid_key');
select pg_temp.check('chave inventada',
  public.submit_import_inbox('fio_' || repeat('0', 64), 'https://www.zara.com/p1', '{}') = 'invalid_key');
select pg_temp.check('chave certa: entregue',
  public.submit_import_inbox((select key from pg_temp.k where who = 'dono'),
    'https://www.zara.com/p1', '{"result":"ok","url":"https://www.zara.com/p1"}',
    array['https://static.zara.net/a.jpg']) = 'ok');
select pg_temp.check('anónimo não lê a caixa',
  not has_table_privilege('anon', 'public.import_inbox', 'select')
  and not has_function_privilege('anon', 'public.list_import_inbox()', 'execute'));
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1', 'dono@example.com');
select pg_temp.check('o dono vê a peça à espera',
  jsonb_array_length(public.list_import_inbox()) = 1
  and public.list_import_inbox() -> 0 ->> 'url' = 'https://www.zara.com/p1'
  and public.list_import_inbox() -> 0 -> 'preview' ->> 'result' = 'ok');
select pg_temp.check('a imagem fica autorizada ao dono',
  public.import_image_allowed('https://static.zara.net/a.jpg'));
select pg_temp.check('a utilização fica registada',
  public.import_inbox_key_status() ->> 'last_used_at' is not null);
insert into pg_temp.k values ('item', public.list_import_inbox() -> 0 ->> 'id');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2', 'outro@example.com');
select pg_temp.check('outro utilizador não vê nem apaga',
  jsonb_array_length(public.list_import_inbox()) = 0);
select public.discard_import_inbox((select key::uuid from pg_temp.k where who = 'item'));
reset role;
select pg_temp.check('continua lá', (select count(*) from public.import_inbox) = 1);
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1', 'dono@example.com');
select public.discard_import_inbox((public.list_import_inbox() -> 0 ->> 'id')::uuid);
select pg_temp.check('descartada pelo dono',
  jsonb_array_length(public.list_import_inbox()) = 0);
select public.revoke_import_inbox_key();
select pg_temp.as_anon();
select pg_temp.check('chave revogada',
  public.submit_import_inbox((select key from pg_temp.k where who = 'dono'),
    'https://www.zara.com/p1', '{}') = 'invalid_key');
commit;

begin;
-- Saiu da allowlist depois de criar a chave.
delete from public.allowed_users where email = 'outro@example.com';
select pg_temp.as_anon();
select pg_temp.check('fora da allowlist: recusado',
  public.submit_import_inbox((select key from pg_temp.k where who = 'outro'),
    'https://www.zara.com/p1', '{}') = 'forbidden');
reset role;
insert into public.allowed_users (email) values ('outro@example.com');
commit;

begin;
select pg_temp.as_anon();
select public.submit_import_inbox((select key from pg_temp.k where who = 'outro'),
  'https://www.zara.com/p' || n, '{}') from generate_series(1, 20) n;
select pg_temp.check('caixa cheia aos 20',
  public.submit_import_inbox((select key from pg_temp.k where who = 'outro'),
    'https://www.zara.com/p21', '{}') = 'full');
reset role;
delete from public.import_inbox;
insert into public.import_requests (owner_id)
  select '00000000-0000-0000-0000-0000000000e2' from generate_series(1, 30);
select pg_temp.as_anon();
select pg_temp.check('a quota das importações vale para o atalho',
  public.submit_import_inbox((select key from pg_temp.k where who = 'outro'),
    'https://www.zara.com/p1', '{}') = 'rate_limited');
commit;

-- A imagem do Pin (até 900 000 caracteres) cabe na pré-visualização.
begin;
reset role;
delete from public.import_inbox;
delete from public.import_requests;
select pg_temp.as_anon();
select pg_temp.check('pré-visualização com a imagem do Pin',
  public.submit_import_inbox((select key from pg_temp.k where who = 'outro'),
    'https://pt.pinterest.com/pin/1/',
    jsonb_build_object('inspiration', jsonb_build_object('image', repeat('A', 900000)))) = 'ok');
commit;

begin;
select pg_temp.as_anon();
do $$
begin
  perform public.submit_import_inbox((select key from pg_temp.k where who = 'outro'),
    'https://pt.pinterest.com/pin/2/',
    jsonb_build_object('inspiration', jsonb_build_object('image', repeat('A', 1100000))));
  raise exception 'FALHOU: aceitou mais de 1 MB';
exception when check_violation then
  raise notice 'ok - mais de 1 MB fica de fora';
end $$;
commit;
