-- Testes dos perfis de domínio e das imagens autorizadas (record_import).
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-0000000000d1', 'dono@example.com'),
  ('00000000-0000-0000-0000-0000000000d2', 'outro@example.com'),
  ('00000000-0000-0000-0000-0000000000d3', 'fora@example.com');
insert into public.allowed_users (email) values ('dono@example.com'), ('outro@example.com');

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
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1', 'dono@example.com');
select pg_temp.check('primeira vez, falhou: site novo',
  public.record_import('loja.example', 'no_metadata') ->> 'status' = 'new');
select pg_temp.check('primeiro sucesso: em teste',
  public.record_import('loja.example', 'ok', 'json-ld', array['https://cdn.loja.example/a.jpg']) ->> 'status' = 'testing');
select public.record_import('loja.example', 'ok', 'json-ld');
select pg_temp.check('três sucessos: funciona',
  public.record_import('loja.example', 'ok', 'microdata') ->> 'status' = 'works');
select pg_temp.check('imagem oferecida: autorizada',
  public.import_image_allowed('https://cdn.loja.example/a.jpg'));
select pg_temp.check('imagem nunca oferecida: recusada',
  not public.import_image_allowed('https://169.254.169.254/a.jpg'));
select public.record_import('loja.example', 'fetch_failed');
select public.record_import('loja.example', 'fetch_failed');
select pg_temp.check('três falhas seguidas: costuma falhar',
  public.record_import('loja.example', 'fetch_failed') ->> 'status' = 'failing');
select pg_temp.check('volta a funcionar: falhas seguidas a zero',
  public.record_import('loja.example', 'ok', 'json-ld') ->> 'status' = 'works');
commit;

begin;
select pg_temp.check('cliente não lê as tabelas',
  not has_table_privilege('authenticated', 'public.import_domains', 'select')
  and not has_table_privilege('authenticated', 'public.import_image_grants', 'select'));
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2', 'outro@example.com');
select pg_temp.check('a imagem de outro utilizador não serve',
  not public.import_image_allowed('https://cdn.loja.example/a.jpg'));
reset role;
update public.import_image_grants set expires_at = now() - interval '1 minute';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1', 'dono@example.com');
select pg_temp.check('autorização expirada',
  not public.import_image_allowed('https://cdn.loja.example/a.jpg'));
commit;

do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d3', 'fora@example.com');
  begin
    perform public.record_import('loja.example', 'ok');
    raise exception 'FALHOU: fora da allowlist devia falhar';
  exception when sqlstate '42501' then
    raise notice 'ok - fora da allowlist falha';
  end;
  perform pg_temp.check('fora da allowlist: imagem recusada',
    not public.import_image_allowed('https://cdn.loja.example/a.jpg'));
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1', 'dono@example.com');
  begin
    perform public.record_import('Loja Inválida', 'ok');
    raise exception 'FALHOU: domínio inválido devia falhar';
  exception when sqlstate '22023' then
    raise notice 'ok - domínio inválido falha';
  end;
  begin
    perform public.record_import('loja.example', 'inventado');
    raise exception 'FALHOU: resultado inválido devia falhar';
  exception when sqlstate '22023' then
    raise notice 'ok - resultado inválido falha';
  end;
end $$;
