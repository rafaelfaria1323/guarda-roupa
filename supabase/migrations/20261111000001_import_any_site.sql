-- Importação de qualquer site (docs/features/importacao-de-links.md).
--
-- import_domains: perfil de cada domínio, criado e atualizado sozinho a cada
-- importação (sucessos, falhas seguidas, de onde vieram os dados). É daqui
-- que sai o estado mostrado na app ("site novo", "costuma funcionar", ...).
-- Só contagens e o domínio: nenhum link, produto ou utilizador.
--
-- import_image_grants: a função só copia uma imagem que ela própria
-- devolveu numa pré-visualização a esse utilizador há menos de um dia. Assim
-- aceitar qualquer site não a torna um proxy de imagens arbitrárias.

create table public.import_domains (
  host text primary key check (char_length(host) between 3 and 253),
  ok_count integer not null default 0,
  fail_count integer not null default 0,
  consecutive_failures integer not null default 0,
  last_result text not null,
  last_source text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
alter table public.import_domains enable row level security;
revoke all on public.import_domains from anon, authenticated;

create table public.import_image_grants (
  owner_id uuid not null,
  url_hash text not null,
  expires_at timestamptz not null,
  primary key (owner_id, url_hash)
);
create index import_image_grants_expiry on public.import_image_grants (expires_at);
alter table public.import_image_grants enable row level security;
revoke all on public.import_image_grants from anon, authenticated;

-- Estado de um domínio a partir das contagens. 'new': ainda sem sucessos;
-- 'works': 3 ou mais sucessos e o último pedido correu bem; 'failing': 3
-- falhas seguidas; 'testing': o resto.
create function public.import_domain_status(d public.import_domains)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when d.consecutive_failures >= 3 then 'failing'
    when d.ok_count >= 3 and d.consecutive_failures = 0 then 'works'
    when d.ok_count = 0 then 'new'
    else 'testing'
  end
$$;

-- Regista o resultado de uma importação e devolve o perfil do domínio.
-- p_images: as imagens oferecidas nesta pré-visualização (no máximo 12).
create function public.record_import(
  p_host text,
  p_result text,
  p_source text default null,
  p_images text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ok boolean := p_result = 'ok';
  v_row public.import_domains;
begin
  if v_uid is null then
    raise exception 'sem sessão' using errcode = '28000';
  end if;
  if not public.is_allowed() then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if p_host is null or p_host !~ '^[a-z0-9.-]{3,253}$' then
    raise exception 'domínio inválido' using errcode = '22023';
  end if;
  if p_result not in ('ok', 'no_metadata', 'fetch_failed') then
    raise exception 'resultado inválido' using errcode = '22023';
  end if;
  if p_source is not null and p_source not in ('json-ld', 'microdata', 'open-graph', 'html') then
    raise exception 'origem inválida' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_images), 0) > 12 then
    raise exception 'demasiadas imagens' using errcode = '22023';
  end if;

  insert into public.import_domains as d (host, ok_count, fail_count, consecutive_failures, last_result, last_source)
  values (p_host, v_ok::int, (not v_ok)::int, (not v_ok)::int, p_result, p_source)
  on conflict (host) do update set
    ok_count = d.ok_count + v_ok::int,
    fail_count = d.fail_count + (not v_ok)::int,
    consecutive_failures = case when v_ok then 0 else d.consecutive_failures + 1 end,
    last_result = excluded.last_result,
    last_source = coalesce(excluded.last_source, d.last_source),
    last_seen = now()
  returning * into v_row;

  delete from public.import_image_grants where expires_at < now();
  insert into public.import_image_grants (owner_id, url_hash, expires_at)
  select v_uid, md5(u), now() + interval '1 day'
    from unnest(coalesce(p_images, '{}')) as u
   where char_length(u) <= 2048
  on conflict (owner_id, url_hash) do update set expires_at = excluded.expires_at;

  return jsonb_build_object(
    'status', public.import_domain_status(v_row),
    'ok_count', v_row.ok_count,
    'fail_count', v_row.fail_count
  );
end;
$$;

-- A imagem foi oferecida a este utilizador numa pré-visualização recente?
create function public.import_image_allowed(p_url text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and public.is_allowed() and exists (
    select 1 from public.import_image_grants
     where owner_id = auth.uid() and url_hash = md5(p_url) and expires_at > now()
  )
$$;

revoke all on function public.import_domain_status(public.import_domains) from public;
revoke all on function public.record_import(text, text, text, text[]) from public;
revoke all on function public.import_image_allowed(text) from public;
grant execute on function public.record_import(text, text, text, text[]) to authenticated;
grant execute on function public.import_image_allowed(text) to authenticated;
