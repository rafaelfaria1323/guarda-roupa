-- Stub mínimo do ambiente Supabase para testar as migrações num PostgreSQL
-- local. NÃO executar no projeto Supabase real.
-- Os roles são globais ao cluster: criar só se ainda não existirem.
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'supabase_auth_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin', r);
    end if;
  end loop;
end $$;
create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (id uuid primary key, email text);

create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid;
$$;
grant execute on all functions in schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
