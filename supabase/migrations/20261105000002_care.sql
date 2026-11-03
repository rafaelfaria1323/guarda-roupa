-- Lavandaria e políticas por categoria/peça (incremento 3;
-- docs/features/lavandaria.md e utilizacao-e-rotatividade.md).
--
-- cleaning_events: "lavei/limpei esta peça neste dia". Reinicia a contagem
--   de utilizações para o aviso de lavagem; não muda a disponibilidade.
-- care_policies: valores escolhidos pelo utilizador que substituem os
--   predefinidos da app (P-06, P-07). Uma linha por (âmbito, alvo):
--   scope = 'category' (alvo = id da categoria) ou 'garment' (alvo = id da
--   peça). null = usar o predefinido; 0 = sem aviso / sem intervalo.
--   O id é determinístico (md5 de dono:âmbito:alvo) para que o mesmo valor
--   escolhido em dois dispositivos seja a mesma linha. Último a escrever
--   ganha, campo a campo.
--
-- As escritas passam por apply_wear_operation (a mesma fila do cliente).

create table public.cleaning_events (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  garment_id uuid not null,
  cleaned_on date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  voided_at timestamptz
);

create index cleaning_events_owner_idx on public.cleaning_events (owner_id, garment_id)
  where voided_at is null;

create table public.care_policies (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  scope text not null check (scope in ('category', 'garment')),
  target text not null check (target ~ '^[a-z_]{1,32}$' or target ~ '^[0-9a-f-]{36}$'),
  laundry_after smallint check (laundry_after between 0 and 30),
  rotation_days smallint check (rotation_days between 0 and 60),
  updated_at timestamptz not null default now(),
  unique (owner_id, scope, target)
);

alter table public.cleaning_events enable row level security;
alter table public.care_policies enable row level security;

create policy cleaning_events_select_own on public.cleaning_events
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());
create policy care_policies_select_own on public.care_policies
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

revoke all on public.cleaning_events, public.care_policies from anon, authenticated;
grant select on public.cleaning_events, public.care_policies to authenticated;

alter publication powersync add table public.cleaning_events, public.care_policies;

-- op = { op_id, event_id, kind, data }
--
-- record_wear:     { worn_on, garment_ids: [uuid, ...], plan_entry_id? }
-- void_wear:       {}
-- record_cleaning: { garment_id, cleaned_on }
-- void_cleaning:   {}
-- set_policy:      { scope, target, laundry_after?, rotation_days? }
--                  (só os campos presentes mudam; null volta ao predefinido;
--                   event_id = md5(dono:scope:target) em forma de uuid)
create or replace function public.apply_wear_operation(op jsonb)
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
  v_owner uuid;
  v_result jsonb;
  v_worn_on date;
  v_plan uuid;
  v_ids jsonb;
  v_known int;
  v_garment uuid;
  v_scope text;
  v_target text;
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

  begin
    if v_kind in ('record_wear', 'void_wear') then
      select owner_id into v_owner from public.wear_events where id = v_event_id for update;
    elsif v_kind in ('record_cleaning', 'void_cleaning') then
      select owner_id into v_owner from public.cleaning_events where id = v_event_id for update;
    end if;

    if v_owner is not null and v_owner <> v_uid then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');

    elsif v_kind = 'record_wear' then
      if v_owner is not null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
      else
        v_worn_on := (v_data ->> 'worn_on')::date;
        v_plan := (v_data ->> 'plan_entry_id')::uuid;
        v_ids := v_data -> 'garment_ids';
        if v_worn_on is null or v_ids is null or not public.wear_garments_valid(v_ids) then
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
      end if;

    elsif v_kind = 'void_wear' then
      if v_owner is null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        update public.wear_events
        set voided_at = coalesce(voided_at, now()), updated_at = now()
        where id = v_event_id;
        v_result := jsonb_build_object('result', 'applied');
      end if;

    elsif v_kind = 'record_cleaning' then
      if v_owner is not null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
      else
        v_garment := (v_data ->> 'garment_id')::uuid;
        if v_garment is null or (v_data ->> 'cleaned_on') is null then
          raise invalid_parameter_value;
        end if;
        if not exists (
          select 1 from public.garments
          where id = v_garment and owner_id = v_uid and deleted_at is null
        ) then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          insert into public.cleaning_events (id, owner_id, garment_id, cleaned_on)
          values (v_event_id, v_uid, v_garment, (v_data ->> 'cleaned_on')::date);
          v_result := jsonb_build_object('result', 'applied');
        end if;
      end if;

    elsif v_kind = 'void_cleaning' then
      if v_owner is null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        update public.cleaning_events
        set voided_at = coalesce(voided_at, now()), updated_at = now()
        where id = v_event_id;
        v_result := jsonb_build_object('result', 'applied');
      end if;

    elsif v_kind = 'set_policy' then
      v_scope := v_data ->> 'scope';
      v_target := v_data ->> 'target';
      if v_scope is null or v_target is null
          or v_event_id <> md5(v_uid::text || ':' || v_scope || ':' || v_target)::uuid
          or not (v_data ? 'laundry_after' or v_data ? 'rotation_days') then
        raise invalid_parameter_value;
      end if;
      if v_scope = 'garment' and not exists (
        select 1 from public.garments
        where id::text = v_target and owner_id = v_uid and deleted_at is null
      ) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        insert into public.care_policies as p
          (id, owner_id, scope, target, laundry_after, rotation_days)
        values (
          v_event_id, v_uid, v_scope, v_target,
          (v_data ->> 'laundry_after')::smallint,
          (v_data ->> 'rotation_days')::smallint
        )
        on conflict (owner_id, scope, target) do update set
          laundry_after = case when v_data ? 'laundry_after'
            then excluded.laundry_after else p.laundry_after end,
          rotation_days = case when v_data ? 'rotation_days'
            then excluded.rotation_days else p.rotation_days end,
          updated_at = now();
        v_result := jsonb_build_object('result', 'applied');
      end if;

    else
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
    end if;
  exception
    when invalid_parameter_value or invalid_text_representation
      or invalid_datetime_format or datetime_field_overflow
      or check_violation or numeric_value_out_of_range then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;

  insert into public.applied_operations (op_id, owner_id, garment_id, kind, result)
  values (v_op_id, v_uid, v_event_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;
