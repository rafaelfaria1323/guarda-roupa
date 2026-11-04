-- Importação de produtos por link (docs/features/importacao-de-links.md):
-- quota por utilizador para a Edge Function `import-product`. A função
-- chama claim_import_quota() com o token do utilizador; a base valida o
-- token, a allowlist (P-16) e o limite. Sem dados de produto: só contagens.

create table public.import_requests (
  id bigint generated always as identity primary key,
  owner_id uuid not null,
  requested_at timestamptz not null default now()
);
create index import_requests_owner_time on public.import_requests (owner_id, requested_at);
alter table public.import_requests enable row level security;
revoke all on public.import_requests from anon, authenticated;

-- 'ok' conta o pedido; 'forbidden' fora da allowlist; 'rate_limited' acima
-- de 30 pedidos na última hora ou 200 no último dia.
create function public.claim_import_quota()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'sem sessão' using errcode = '28000';
  end if;
  if not public.is_allowed() then
    return 'forbidden';
  end if;
  perform pg_advisory_xact_lock(hashtext('import:' || v_uid::text));
  delete from public.import_requests
    where owner_id = v_uid and requested_at < now() - interval '1 day';
  if (select count(*) from public.import_requests
        where owner_id = v_uid and requested_at > now() - interval '1 hour') >= 30
     or (select count(*) from public.import_requests where owner_id = v_uid) >= 200 then
    return 'rate_limited';
  end if;
  insert into public.import_requests (owner_id) values (v_uid);
  return 'ok';
end;
$$;

revoke all on function public.claim_import_quota() from public;
grant execute on function public.claim_import_quota() to authenticated;
