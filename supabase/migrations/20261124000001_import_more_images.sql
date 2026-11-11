-- "Ver todas as imagens da página": além das fotos do produto (até 12), a
-- pré-visualização pode oferecer as outras imagens da página que o atalho
-- mandou. O limite de imagens autorizadas por pedido passa de 12 para 40.
create or replace function public.record_import(
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
  if p_result not in ('ok', 'no_metadata', 'fetch_failed', 'shared') then
    raise exception 'resultado inválido' using errcode = '22023';
  end if;
  if p_source is not null and p_source not in ('json-ld', 'microdata', 'open-graph', 'html') then
    raise exception 'origem inválida' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_images), 0) > 40 then
    raise exception 'demasiadas imagens' using errcode = '22023';
  end if;

  if p_result = 'shared' then
    -- Página aberta pelo utilizador no browser e partilhada (atalho do
    -- iPhone): não diz nada sobre o link funcionar, por isso não conta.
    select * into v_row from public.import_domains where host = p_host;
  else
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
  end if;

  delete from public.import_image_grants where expires_at < now();
  insert into public.import_image_grants (owner_id, url_hash, expires_at)
  select v_uid, md5(u), now() + interval '1 day'
    from unnest(coalesce(p_images, '{}')) as u
   where char_length(u) <= 2048
  on conflict (owner_id, url_hash) do update set expires_at = excluded.expires_at;

  if v_row.host is null then
    return jsonb_build_object('status', 'new', 'ok_count', 0, 'fail_count', 0);
  end if;
  return jsonb_build_object(
    'status', public.import_domain_status(v_row),
    'ok_count', v_row.ok_count,
    'fail_count', v_row.fail_count
  );
end;
$$;

create or replace function public.submit_import_inbox(
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
     or coalesce(cardinality(p_images), 0) > 40 then
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
