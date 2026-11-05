-- Caixa "Por importar": o atalho do iPhone manda a página da peça direto
-- para o fio (docs/features/importacao-de-links.md#atalho-do-iphone).
--
-- O atalho não tem sessão. Autentica-se com uma chave pessoal criada na
-- app (create_import_inbox_key), da qual só se guarda o SHA-256. A função
-- import-product lê a página que o atalho mandou e entrega a pré-
-- visualização com submit_import_inbox. A app lista-a (list_import_inbox)
-- e apaga-a depois de usada ou descartada.
--
-- Nada disto sincroniza nem entra no backup: são pedidos de passagem, que
-- expiram ao fim de 7 dias.

create table public.import_inbox_keys (
  owner_id uuid primary key,
  key_hash text not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);
alter table public.import_inbox_keys enable row level security;
revoke all on public.import_inbox_keys from anon, authenticated;

create table public.import_inbox (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  url text not null check (char_length(url) <= 2048),
  preview jsonb not null check (octet_length(preview::text) <= 65536),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days'
);
create index import_inbox_owner on public.import_inbox (owner_id, created_at);
alter table public.import_inbox enable row level security;
revoke all on public.import_inbox from anon, authenticated;

create function public.import_inbox_hash(p_key text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to(p_key, 'UTF8')), 'hex')
$$;

-- Nova chave do atalho (substitui a anterior). Devolvida só agora.
create function public.create_import_inbox_key()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_key text;
begin
  if v_uid is null then
    raise exception 'sem sessão' using errcode = '28000';
  end if;
  if not public.is_allowed() then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  -- 244 bits aleatórios (duas UUID v4), sem extensões.
  v_key := 'fio_' || replace(gen_random_uuid()::text, '-', '')
                   || replace(gen_random_uuid()::text, '-', '');
  insert into public.import_inbox_keys (owner_id, key_hash)
  values (v_uid, public.import_inbox_hash(v_key))
  on conflict (owner_id) do update set
    key_hash = excluded.key_hash, created_at = now(), last_used_at = null;
  return v_key;
end;
$$;

-- Desliga o atalho: a chave deixa de servir.
create function public.revoke_import_inbox_key()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'sem sessão' using errcode = '28000';
  end if;
  delete from public.import_inbox_keys where owner_id = auth.uid();
end;
$$;

-- Há uma chave ativa? E quando foi usada pela última vez?
create function public.import_inbox_key_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when auth.uid() is null then null else coalesce(
    (select jsonb_build_object('active', true, 'created_at', k.created_at,
                               'last_used_at', k.last_used_at)
       from public.import_inbox_keys k where k.owner_id = auth.uid()),
    jsonb_build_object('active', false)) end
$$;

-- Chamada pela função import-product com o que o atalho mandou, sem
-- sessão. A chave identifica o dono; valem a allowlist e a quota dele.
-- Resultados: ok, invalid_key, forbidden, rate_limited, full.
create function public.submit_import_inbox(
  p_key text,
  p_url text,
  p_preview jsonb,
  p_images text[] default '{}'
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  if p_key is null or char_length(p_key) not between 20 and 200 then
    return 'invalid_key';
  end if;
  select owner_id into v_owner from public.import_inbox_keys
   where key_hash = public.import_inbox_hash(p_key);
  if v_owner is null then
    return 'invalid_key';
  end if;
  if not exists (
    select 1 from auth.users u
      join public.allowed_users a on a.email = lower(u.email)
     where u.id = v_owner
  ) then
    return 'forbidden';
  end if;
  if p_url is null or char_length(p_url) > 2048 or p_preview is null
     or coalesce(cardinality(p_images), 0) > 12 then
    raise exception 'pedido inválido' using errcode = '22023';
  end if;

  -- A mesma quota das importações com sessão.
  perform pg_advisory_xact_lock(hashtext('import:' || v_owner::text));
  delete from public.import_requests
    where owner_id = v_owner and requested_at < now() - interval '1 day';
  if (select count(*) from public.import_requests
        where owner_id = v_owner and requested_at > now() - interval '1 hour') >= 30
     or (select count(*) from public.import_requests where owner_id = v_owner) >= 200 then
    return 'rate_limited';
  end if;

  delete from public.import_inbox where expires_at < now();
  if (select count(*) from public.import_inbox where owner_id = v_owner) >= 20 then
    return 'full';
  end if;

  insert into public.import_requests (owner_id) values (v_owner);
  insert into public.import_inbox (owner_id, url, preview)
  values (v_owner, p_url, p_preview);
  update public.import_inbox_keys set last_used_at = now() where owner_id = v_owner;

  -- As imagens oferecidas ficam autorizadas enquanto a peça espera.
  insert into public.import_image_grants (owner_id, url_hash, expires_at)
  select v_owner, md5(u), now() + interval '7 days'
    from unnest(coalesce(p_images, '{}')) as u
   where char_length(u) <= 2048
  on conflict (owner_id, url_hash) do update
    set expires_at = greatest(public.import_image_grants.expires_at, excluded.expires_at);
  return 'ok';
end;
$$;

-- As peças à espera, da mais recente para a mais antiga.
create function public.list_import_inbox()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'url', i.url, 'preview', i.preview,
           'created_at', i.created_at) order by i.created_at desc), '[]'::jsonb)
    from public.import_inbox i
   where auth.uid() is not null and public.is_allowed()
     and i.owner_id = auth.uid() and i.expires_at > now()
$$;

-- Usada ou descartada: sai da caixa.
create function public.discard_import_inbox(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'sem sessão' using errcode = '28000';
  end if;
  delete from public.import_inbox where id = p_id and owner_id = auth.uid();
end;
$$;

revoke all on function public.import_inbox_hash(text) from public;
revoke all on function public.create_import_inbox_key() from public;
revoke all on function public.revoke_import_inbox_key() from public;
revoke all on function public.import_inbox_key_status() from public;
revoke all on function public.submit_import_inbox(text, text, jsonb, text[]) from public;
revoke all on function public.list_import_inbox() from public;
revoke all on function public.discard_import_inbox(uuid) from public;
grant execute on function public.create_import_inbox_key() to authenticated;
grant execute on function public.revoke_import_inbox_key() to authenticated;
grant execute on function public.import_inbox_key_status() to authenticated;
grant execute on function public.submit_import_inbox(text, text, jsonb, text[]) to anon, authenticated;
grant execute on function public.list_import_inbox() to authenticated;
grant execute on function public.discard_import_inbox(uuid) to authenticated;
