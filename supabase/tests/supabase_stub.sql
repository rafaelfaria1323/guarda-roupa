-- Stub mínimo do ambiente Supabase para testar as migrações num PostgreSQL
-- local. NÃO executar no projeto Supabase real.
-- Os roles são globais ao cluster: criar só se ainda não existirem.
-- powersync_role: no projeto real é criado à mão (guia 08 §4).
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'supabase_auth_admin', 'powersync_role'] loop
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

-- Storage: só o necessário para as políticas e para attach_photo.
create schema storage;
grant usage on schema storage to anon, authenticated;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid default auth.uid(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant select, insert, delete on storage.objects to authenticated;
create function storage.foldername(name text) returns text[]
language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1];
$$;
grant execute on all functions in schema storage to anon, authenticated;
