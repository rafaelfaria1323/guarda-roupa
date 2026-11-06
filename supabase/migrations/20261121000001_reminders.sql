-- Lembretes por notificação (docs/features/lembretes.md, 2026-11-06).
--
-- Dois lembretes, cada um à hora escolhida pelo utilizador (null = desligado),
-- na hora local do fuso guardado:
--   wear_check  "Vestiste isto?": ao fim do dia, se há roupa planeada e ainda
--               nada registado nesse dia (nunca conta como utilização sozinho:
--               abre o "Vesti hoje" para confirmar);
--   eve         "Amanhã: …": na véspera, se o dia seguinte tem roupa planeada.
--
-- A app escreve o texto de cada dia (day_summaries), com os nomes das peças e
-- os acessórios pelo tempo; o servidor só o usa se a entrada do plano ainda
-- estiver na mesma versão, senão manda um texto genérico.
--
-- Quem envia é a Edge Function `reminders`, chamada pelo pg_cron de 5 em 5
-- minutos (agendado pelo workflow "Supabase"). A função não tem privilégios:
-- passa à base o token que recebeu do cron (gerado aqui, nunca sai da base) e
-- só com ele claim_due_reminders devolve alguma coisa. Cada lembrete fica em
-- reminder_sends: nunca sai duas vezes, mesmo com chamadas repetidas.

create schema if not exists private;
revoke all on schema private from public;

create table private.reminder_cron (
  id boolean primary key default true check (id),
  token text not null
);
insert into private.reminder_cron (token)
values (replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''));

create function private.reminder_token_ok(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.reminder_cron
    where p_token is not null and token = p_token
  );
$$;
revoke all on function private.reminder_token_ok(text) from public;

-- Um por aparelho (o endpoint do serviço de push do navegador).
create table public.push_subscriptions (
  endpoint text primary key
    check (endpoint ~ '^https://' and length(endpoint) <= 1000),
  owner_id uuid not null references auth.users (id) on delete cascade,
  p256dh text not null check (length(p256dh) between 40 and 200),
  auth text not null check (length(auth) between 10 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index push_subscriptions_owner_idx on public.push_subscriptions (owner_id);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;

create table public.reminder_settings (
  owner_id uuid primary key references auth.users (id) on delete cascade,
  wear_check_at time,
  eve_at time,
  time_zone text not null,
  updated_at timestamptz not null default now()
);
alter table public.reminder_settings enable row level security;
revoke all on public.reminder_settings from anon, authenticated;
grant select on public.reminder_settings to authenticated;
create policy reminder_settings_select_own on public.reminder_settings
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

create table public.day_summaries (
  owner_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  plan_version integer not null check (plan_version >= 1),
  wear_body text check (length(wear_body) <= 300),
  eve_body text check (length(eve_body) <= 300),
  updated_at timestamptz not null default now(),
  primary key (owner_id, day)
);
alter table public.day_summaries enable row level security;
revoke all on public.day_summaries from anon, authenticated;

create table public.reminder_sends (
  owner_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('wear_check', 'eve')),
  sent_at timestamptz not null default now(),
  primary key (owner_id, day, kind)
);
alter table public.reminder_sends enable row level security;
revoke all on public.reminder_sends from anon, authenticated;

create function public.save_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_allowed() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  -- O mesmo aparelho com outra conta passa a ser dessa conta.
  insert into public.push_subscriptions (endpoint, owner_id, p256dh, auth)
  values (p_endpoint, auth.uid(), p_p256dh, p_auth)
  on conflict (endpoint) do update
    set owner_id = excluded.owner_id, p256dh = excluded.p256dh,
      auth = excluded.auth, updated_at = now();
end;
$$;

create function public.remove_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions
  where endpoint = p_endpoint and owner_id = auth.uid();
$$;

create function public.set_reminder_settings(
  p_wear_check_at time, p_eve_at time, p_time_zone text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_allowed() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone) then
    raise exception 'invalid time zone' using errcode = '22023';
  end if;
  insert into public.reminder_settings (owner_id, wear_check_at, eve_at, time_zone)
  values (auth.uid(), p_wear_check_at, p_eve_at, p_time_zone)
  on conflict (owner_id) do update
    set wear_check_at = excluded.wear_check_at, eve_at = excluded.eve_at,
      time_zone = excluded.time_zone, updated_at = now();
end;
$$;

-- p_days: [{day, plan_version, wear_body, eve_body}], no máximo 14.
-- Substitui os textos desses dias e apaga os de dias já passados.
create function public.set_day_summaries(p_days jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_allowed() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days) > 14 then
    raise exception 'invalid days' using errcode = '22023';
  end if;
  insert into public.day_summaries (owner_id, day, plan_version, wear_body, eve_body)
  select auth.uid(), (d ->> 'day')::date, (d ->> 'plan_version')::integer,
    nullif(d ->> 'wear_body', ''), nullif(d ->> 'eve_body', '')
  from jsonb_array_elements(p_days) as d
  on conflict (owner_id, day) do update
    set plan_version = excluded.plan_version, wear_body = excluded.wear_body,
      eve_body = excluded.eve_body, updated_at = now();
  delete from public.day_summaries
  where owner_id = auth.uid() and day < current_date - 2;
end;
$$;

revoke all on function public.save_push_subscription(text, text, text) from public;
revoke all on function public.remove_push_subscription(text) from public;
revoke all on function public.set_reminder_settings(time, time, text) from public;
revoke all on function public.set_day_summaries(jsonb) from public;
grant execute on function public.save_push_subscription(text, text, text) to authenticated;
grant execute on function public.remove_push_subscription(text) to authenticated;
grant execute on function public.set_reminder_settings(time, time, text) to authenticated;
grant execute on function public.set_day_summaries(jsonb) to authenticated;

-- Janela depois da hora marcada em que o lembrete ainda sai (o cron pode
-- atrasar-se); nunca passa para o dia seguinte.
create function public.reminder_due(local_now timestamp, at time)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select at is not null
    and local_now >= local_now::date + at
    and local_now < least(local_now::date + at + interval '2 hours',
      local_now::date + 1);
$$;

-- Os lembretes que chegaram à hora, marcados como enviados de uma vez (só o
-- primeiro pedido os recebe). Só com o token do cron.
create function public.claim_due_reminders(p_token text, p_now timestamptz default now())
returns table (kind text, day date, title text, body text, url text, subscriptions jsonb)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not private.reminder_token_ok(p_token) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
  with s as (
    select r.owner_id, (p_now at time zone r.time_zone) as local_now,
      r.wear_check_at, r.eve_at
    from public.reminder_settings r
    where exists (select 1 from public.push_subscriptions p where p.owner_id = r.owner_id)
      and exists (select 1 from public.allowed_users a
        join auth.users u on lower(u.email) = a.email where u.id = r.owner_id)
  ),
  due as (
    select s.owner_id, 'wear_check'::text as kind, s.local_now::date as day
    from s where public.reminder_due(s.local_now, s.wear_check_at)
    union all
    select s.owner_id, 'eve', s.local_now::date + 1
    from s where public.reminder_due(s.local_now, s.eve_at)
  ),
  content as (
    select d.owner_id, d.kind, d.day, e.id as entry_id, e.items,
      case when sm.plan_version = e.version
        then case d.kind when 'eve' then sm.eve_body else sm.wear_body end
      end as written
    from due d
    left join public.plan_entries e
      on e.owner_id = d.owner_id and e.day = d.day and e.deleted_at is null
        and jsonb_array_length(e.items) > 0
    left join public.day_summaries sm on sm.owner_id = d.owner_id and sm.day = d.day
    where case d.kind
      when 'eve' then e.id is not null
      else not exists (
          select 1 from public.wear_events w
          where w.owner_id = d.owner_id and w.worn_on = d.day and w.voided_at is null)
        and exists (
          select 1 from public.garments g
          where g.owner_id = d.owner_id and g.deleted_at is null and g.archived_at is null)
    end
  ),
  claimed as (
    insert into public.reminder_sends as rs (owner_id, day, kind)
    select c.owner_id, c.day, c.kind from content c
    on conflict on constraint reminder_sends_pkey do nothing
    returning rs.owner_id, rs.day, rs.kind
  )
  select c.kind, c.day, 'fio'::text,
    coalesce(c.written, case
      when c.kind = 'eve' then 'Já tens roupa planeada para amanhã. Toca para ver.'
      when c.entry_id is not null then 'Vestiste o que estava planeado para hoje? Toca para confirmar.'
      else 'Ainda não registaste o que vestiste hoje.'
    end),
    case
      when c.kind = 'eve' then '/planeador'
      when c.entry_id is null then '/vesti'
      else '/vesti?pecas=' || (
          select string_agg(i ->> 'garment_id', ',' order by n)
          from jsonb_array_elements(c.items) with ordinality as t(i, n))
        || '&plano=' || c.entry_id
    end,
    (select jsonb_agg(jsonb_build_object('endpoint', p.endpoint, 'p256dh', p.p256dh,
        'auth', p.auth))
      from public.push_subscriptions p where p.owner_id = c.owner_id)
  from content c
  join claimed k on k.owner_id = c.owner_id and k.day = c.day and k.kind = c.kind;
end;
$$;

-- Aparelhos que o serviço de push deu como desaparecidos (404/410).
create function public.drop_push_subscriptions(p_token text, p_endpoints text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.reminder_token_ok(p_token) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.push_subscriptions where endpoint = any (p_endpoints);
end;
$$;

revoke all on function public.reminder_due(timestamp, time) from public;
revoke all on function public.claim_due_reminders(text, timestamptz) from public;
revoke all on function public.drop_push_subscriptions(text, text[]) from public;
-- A função `reminders` chama-as como anónimo; o token é a autorização.
grant execute on function public.claim_due_reminders(text, timestamptz) to anon;
grant execute on function public.drop_push_subscriptions(text, text[]) to anon;
