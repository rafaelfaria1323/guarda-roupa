-- Testes da quota de importação (claim_import_quota).
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
select pg_temp.check('primeiro pedido conta', public.claim_import_quota() = 'ok');
select pg_temp.check('29 seguintes também',
  (select bool_and(public.claim_import_quota() = 'ok') from generate_series(1, 29)));
select pg_temp.check('31.º na mesma hora: limite', public.claim_import_quota() = 'rate_limited');
commit;

begin;
select pg_temp.check('cliente não lê a tabela', not has_table_privilege(
  'authenticated', 'public.import_requests', 'select'));
-- Pedidos antigos deixam de contar e são apagados.
update public.import_requests set requested_at = now() - interval '2 days';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');
select pg_temp.check('dia seguinte: volta a haver quota', public.claim_import_quota() = 'ok');
reset role;
select pg_temp.check('antigos apagados', (select count(*) from public.import_requests) = 1);
commit;

begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.check('fora da allowlist', public.claim_import_quota() = 'forbidden');
reset role;
select pg_temp.check('não contou', (select count(*) from public.import_requests) = 1);
commit;

do $$
begin
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.claim_import_quota();
    raise exception 'FALHOU: sem sessão devia falhar';
  exception when sqlstate '28000' then
    raise notice 'ok - sem sessão falha';
  end;
end $$;
