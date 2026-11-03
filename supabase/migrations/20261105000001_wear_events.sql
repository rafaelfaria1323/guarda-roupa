-- Utilizações reais (incremento 3; docs/features/utilizacao-e-rotatividade.md).
--
-- Um wear_event é "vesti estas peças neste dia", confirmado pelo utilizador.
-- Planear não cria eventos. Desfazer marca voided_at (sai da sincronização);
-- corrigir = desfazer + registar de novo. A mesma entrada de plano
-- confirmada em dois dispositivos dá uma única utilização (plan_entry_id).
--
-- Escritas só por apply_wear_operation(op), idempotente por op_id (partilha
-- applied_operations com as operações de peças; garment_id = id do evento).

create function public.wear_garments_valid(ids jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(ids) = 'array'
    and jsonb_array_length(ids) between 1 and 30
    and (
      select count(*) = count(distinct value)
        and bool_and(value ~ '^[0-9a-fA-F-]{36}$')
      from jsonb_array_elements_text(ids)
    );
$$;

create table public.wear_events (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  worn_on date not null,
  garment_ids jsonb not null check (public.wear_garments_valid(garment_ids)),
  plan_entry_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  voided_at timestamptz
);

create index wear_events_owner_idx on public.wear_events (owner_id, worn_on)
  where voided_at is null;
create unique index wear_events_plan_entry_idx
  on public.wear_events (owner_id, plan_entry_id)
  where plan_entry_id is not null and voided_at is null;

alter table public.wear_events enable row level security;

create policy wear_events_select_own on public.wear_events
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

revoke all on public.wear_events from anon, authenticated;
grant select on public.wear_events to authenticated;

alter publication powersync add table public.wear_events;

-- op = { op_id, event_id, kind: "record_wear" | "void_wear", data }
--
-- record_wear: { worn_on: "AAAA-MM-DD", garment_ids: [uuid, ...],
--                plan_entry_id? }
--   Todas as peças têm de ser do utilizador e não eliminadas (arquivadas
--   podem: o registo pode ser tardio). Uma entrada de plano já confirmada
--   devolve "merged" sem criar outra utilização.
-- void_wear:   {}   (repetir é inofensivo)
create function public.apply_wear_operation(op jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op_id uuid;
  v_event_id uuid;
  v_kind text := op ->> 'kind';
  v_data jsonb := coalesce(op -> 'data', '{}'::jsonb);
  v_existing public.applied_operations;
  v_row public.wear_events;
  v_result jsonb;
  v_worn_on date;
  v_plan uuid;
  v_ids jsonb;
  v_known int;
begin
  if v_uid is null or not public.is_allowed() then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
  end if;

  begin
    v_op_id := (op ->> 'op_id')::uuid;
    v_event_id := (op ->> 'event_id')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;
  if v_op_id is null or v_event_id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_op_id::text, 0));
  select * into v_existing from public.applied_operations where op_id = v_op_id;
  if found then
    if v_existing.owner_id <> v_uid then
      return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
    end if;
    return v_existing.result;
  end if;

  select * into v_row from public.wear_events where id = v_event_id for update;

  if found and v_row.owner_id <> v_uid then
    v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
  elsif v_kind = 'record_wear' then
    if found then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
    else
      begin
        v_worn_on := (v_data ->> 'worn_on')::date;
        v_plan := (v_data ->> 'plan_entry_id')::uuid;
        v_ids := v_data -> 'garment_ids';
        if v_worn_on is null or v_ids is null
            or not public.wear_garments_valid(v_ids) then
          raise invalid_parameter_value;
        end if;
        select count(*) into v_known
        from public.garments g
        where g.owner_id = v_uid and g.deleted_at is null
          and g.id::text in (select jsonb_array_elements_text(v_ids));
        if v_known <> jsonb_array_length(v_ids) then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        elsif v_plan is not null and exists (
          select 1 from public.wear_events
          where owner_id = v_uid and plan_entry_id = v_plan and voided_at is null
        ) then
          v_result := jsonb_build_object('result', 'merged', 'reason', 'plan_already_confirmed');
        else
          insert into public.wear_events (id, owner_id, worn_on, garment_ids, plan_entry_id)
          values (v_event_id, v_uid, v_worn_on, v_ids, v_plan);
          v_result := jsonb_build_object('result', 'applied');
        end if;
      exception
        when invalid_parameter_value or invalid_text_representation
          or invalid_datetime_format or datetime_field_overflow
          or check_violation then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      end;
    end if;
  elsif v_kind = 'void_wear' then
    if not found then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
    else
      update public.wear_events
      set voided_at = coalesce(voided_at, now()), updated_at = now()
      where id = v_event_id;
      v_result := jsonb_build_object('result', 'applied');
    end if;
  else
    v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end if;

  insert into public.applied_operations (op_id, owner_id, garment_id, kind, result)
  values (v_op_id, v_uid, v_event_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;

revoke all on function public.apply_wear_operation(jsonb) from public, anon;
grant execute on function public.apply_wear_operation(jsonb) to authenticated;
