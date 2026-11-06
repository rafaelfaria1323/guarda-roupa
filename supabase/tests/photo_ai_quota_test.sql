-- Testes da quota da leitura de fotos (claim_photo_ai_quota).
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'eu@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
insert into public.allowed_users (email) values ('eu@example.com');

create function pg_temp.as_user(sub text, email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', sub, 'email', email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.check('60 pedidos na mesma hora',
  (select bool_and(public.claim_photo_ai_quota() = 'ok') from generate_series(1, 60)));
select pg_temp.check('61.º: limite', public.claim_photo_ai_quota() = 'rate_limited');
commit;

begin;
select pg_temp.check('cliente não lê a tabela', not has_table_privilege(
  'authenticated', 'public.photo_ai_requests', 'select'));
-- 299 pedidos há mais de uma hora: só falta 1 para o limite do dia.
update public.photo_ai_requests set requested_at = now() - interval '2 hours';
insert into public.photo_ai_requests (owner_id, requested_at)
  select '00000000-0000-0000-0000-00000000000a', now() - interval '3 hours'
  from generate_series(1, 239);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.check('300.º do dia ainda passa', public.claim_photo_ai_quota() = 'ok');
select pg_temp.check('301.º do dia: limite', public.claim_photo_ai_quota() = 'rate_limited');
commit;

begin;
reset role;
update public.photo_ai_requests set requested_at = now() - interval '2 days';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.check('dia seguinte: volta a haver quota', public.claim_photo_ai_quota() = 'ok');
reset role;
select pg_temp.check('antigos apagados', (select count(*) from public.photo_ai_requests) = 1);
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.check('fora da allowlist', public.claim_photo_ai_quota() = 'forbidden');
commit;
