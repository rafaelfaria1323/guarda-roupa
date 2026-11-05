-- Importação de uma página partilhada pelo atalho do iPhone
-- (docs/features/importacao-de-links.md#atalho-do-iphone).
--
-- record_import aceita o resultado 'shared': o utilizador abriu a página no
-- próprio browser e o atalho mandou os dados. Autoriza as imagens oferecidas,
-- como antes, mas não mexe nas contagens do domínio: o perfil diz se o link
-- funciona sozinho, e uma loja que bloqueia continua a "costumar falhar".

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
  if coalesce(cardinality(p_images), 0) > 12 then
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
