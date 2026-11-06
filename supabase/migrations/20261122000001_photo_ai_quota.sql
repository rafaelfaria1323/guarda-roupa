-- Quota da leitura de fotos com o Gemini (docs/features/ia-gemini.md).
-- A Edge Function `describe-photo` chama claim_photo_ai_quota() com o token
-- do utilizador; a base valida o token, a allowlist (P-16) e o limite, que
-- protege a quota grátis do Gemini. Sem fotos nem resultados: só contagens.

create table public.photo_ai_requests (
  id bigint generated always as identity primary key,
  owner_id uuid not null,
  requested_at timestamptz not null default now()
);
create index photo_ai_requests_owner_time
  on public.photo_ai_requests (owner_id, requested_at);
alter table public.photo_ai_requests enable row level security;
revoke all on public.photo_ai_requests from anon, authenticated;

-- 'ok' conta o pedido; 'forbidden' fora da allowlist; 'rate_limited' acima
-- de 60 pedidos na última hora ou 300 no último dia.
create function public.claim_photo_ai_quota()
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
  perform pg_advisory_xact_lock(hashtext('photo_ai:' || v_uid::text));
  delete from public.photo_ai_requests
    where owner_id = v_uid and requested_at < now() - interval '1 day';
  if (select count(*) from public.photo_ai_requests
        where owner_id = v_uid and requested_at > now() - interval '1 hour') >= 60
     or (select count(*) from public.photo_ai_requests where owner_id = v_uid) >= 300 then
    return 'rate_limited';
  end if;
  insert into public.photo_ai_requests (owner_id) values (v_uid);
  return 'ok';
end;
$$;

revoke all on function public.claim_photo_ai_quota() from public;
grant execute on function public.claim_photo_ai_quota() to authenticated;
