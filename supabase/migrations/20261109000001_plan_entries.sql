-- Plano semanal (incremento 6; docs/features/planeamento-semanal.md, P-19).
--
-- Uma entrada por dia (no máximo uma ativa por utilizador e dia): a ocasião
-- (null = "a decidir"), se o dia é provisório (fim de semana: pode não
-- acontecer nada que peça esta roupa), as peças com o papel de cada uma
-- (como em outfits.items, mas pode estar vazio) e o estado (proposed =
-- sugerido, accepted = aceite pelo utilizador). Um plano nunca conta como
-- utilização: só "Vesti hoje" cria wear_events (com plan_entry_id).
--
-- ADR-008: version é incrementada no servidor a cada alteração aplicada.
-- Uma edição com base_version desatualizada não se aplica: fica em
-- proposal (proposta pendente) para o utilizador aceitar ou rejeitar. Criar
-- uma entrada para um dia que já tem outra (dois dispositivos offline) faz
-- o mesmo na entrada existente.
--
-- Escritas só por apply_plan_operation(op), idempotente por op_id
-- (applied_operations; garment_id = id da entrada).

create function public.plan_items_valid(items jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select items = '[]'::jsonb or public.outfit_items_valid(items);
$$;

-- Campos editáveis presentes em data são válidos (os ausentes não contam).
create function public.plan_fields_valid(data jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(data) = 'object'
    and (not data ? 'occasion' or jsonb_typeof(data -> 'occasion') = 'null'
      or data -> 'occasion' in ('"casual"', '"work_casual"', '"evening"'))
    and (not data ? 'tentative' or jsonb_typeof(data -> 'tentative') = 'boolean')
    and (not data ? 'items' or public.plan_items_valid(data -> 'items'))
    and (not data ? 'status' or data -> 'status' in ('"proposed"', '"accepted"'));
$$;

create table public.plan_entries (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  occasion text check (occasion in ('casual', 'work_casual', 'evening')),
  tentative boolean not null default false,
  items jsonb not null default '[]' check (public.plan_items_valid(items)),
  status text not null default 'proposed'
    check (status in ('proposed', 'accepted')),
  version integer not null default 1 check (version >= 1),
  proposal jsonb check (proposal is null or public.plan_fields_valid(proposal)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index plan_entries_owner_day_idx on public.plan_entries (owner_id, day)
  where deleted_at is null;

alter table public.plan_entries enable row level security;

create policy plan_entries_select_own on public.plan_entries
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

revoke all on public.plan_entries from anon, authenticated;
grant select on public.plan_entries to authenticated;

alter publication powersync add table public.plan_entries;

-- Só os campos editáveis de data (para guardar como proposta).
create function public.plan_changes(data jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from jsonb_each(data)
  where key in ('occasion', 'tentative', 'items', 'status');
$$;

-- op = { op_id, entry_id, kind, data }
--
-- create_plan_entry:     { day, occasion?, tentative?, items?, status? }
--                        Dia já ocupado: conflict/day_taken, com a proposta
--                        guardada na entrada existente (entry_id na resposta).
-- edit_plan_entry:       { base_version, occasion?, tentative?, items?,
--                        status? }  só os campos presentes mudam. Com
--                        base_version desatualizada: conflict/stale e a
--                        alteração fica em proposal.
-- resolve_plan_proposal: { accept }  aceitar aplica a proposta; rejeitar
--                        descarta-a.
-- delete_plan_entry:     {}  (repetir é inofensivo; liberta o dia)
create function public.apply_plan_operation(op jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op_id uuid;
  v_entry_id uuid;
  v_kind text := op ->> 'kind';
  v_data jsonb := coalesce(op -> 'data', '{}'::jsonb);
  v_existing public.applied_operations;
  v_row public.plan_entries;
  v_other public.plan_entries;
  v_result jsonb;
  v_changes jsonb;
  v_day date;
begin
  if v_uid is null or not public.is_allowed() then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
  end if;

  begin
    v_op_id := (op ->> 'op_id')::uuid;
    v_entry_id := (op ->> 'entry_id')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;
  if v_op_id is null or v_entry_id is null or jsonb_typeof(v_data) <> 'object' then
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
  -- Um dia de cada vez por utilizador: dois creates do mesmo dia não correm.
  perform pg_advisory_xact_lock(hashtextextended('plan:' || v_uid::text, 0));

  select * into v_row from public.plan_entries where id = v_entry_id for update;
  v_changes := public.plan_changes(v_data);

  begin
    if found and v_row.owner_id <> v_uid then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
    elsif v_kind = 'create_plan_entry' then
      begin
        v_day := (v_data ->> 'day')::date;
      exception when invalid_text_representation or datetime_field_overflow then
        v_day := null;
      end;
      if found then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
      elsif v_day is null or not public.plan_fields_valid(v_changes) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      elsif not public.outfit_garments_known(v_uid,
          coalesce(v_changes -> 'items', '[]'::jsonb)) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        select * into v_other from public.plan_entries
        where owner_id = v_uid and day = v_day and deleted_at is null
        for update;
        if found then
          update public.plan_entries set proposal = v_changes, updated_at = now()
          where id = v_other.id;
          v_result := jsonb_build_object('result', 'conflict', 'reason', 'day_taken',
            'entry_id', v_other.id);
        else
          insert into public.plan_entries (id, owner_id, day, occasion, tentative,
            items, status)
          values (v_entry_id, v_uid, v_day, v_changes ->> 'occasion',
            coalesce((v_changes ->> 'tentative')::boolean, false),
            coalesce(v_changes -> 'items', '[]'::jsonb),
            coalesce(v_changes ->> 'status', 'proposed'));
          v_result := jsonb_build_object('result', 'applied');
        end if;
      end if;
    elsif v_kind = 'edit_plan_entry' then
      if not found or v_row.deleted_at is not null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif jsonb_typeof(v_data -> 'base_version') is distinct from 'number'
          or v_changes = '{}'::jsonb or not public.plan_fields_valid(v_changes) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      elsif v_changes ? 'items'
          and not public.outfit_garments_known(v_uid, v_changes -> 'items') then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif (v_data ->> 'base_version')::integer <> v_row.version then
        update public.plan_entries set proposal = v_changes, updated_at = now()
        where id = v_entry_id;
        v_result := jsonb_build_object('result', 'conflict', 'reason', 'stale',
          'entry_id', v_entry_id);
      else
        update public.plan_entries set
          occasion = case when v_changes ? 'occasion'
            then v_changes ->> 'occasion' else occasion end,
          tentative = coalesce((v_changes ->> 'tentative')::boolean, tentative),
          items = coalesce(v_changes -> 'items', items),
          status = coalesce(v_changes ->> 'status', status),
          version = version + 1,
          updated_at = now()
        where id = v_entry_id;
        v_result := jsonb_build_object('result', 'applied');
      end if;
    elsif v_kind = 'resolve_plan_proposal' then
      if not found or v_row.deleted_at is not null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif jsonb_typeof(v_data -> 'accept') is distinct from 'boolean' then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      elsif v_row.proposal is null then
        -- Já resolvida noutro dispositivo: nada a fazer.
        v_result := jsonb_build_object('result', 'applied');
      elsif (v_data ->> 'accept')::boolean then
        v_changes := v_row.proposal;
        if v_changes ? 'items'
            and not public.outfit_garments_known(v_uid, v_changes -> 'items') then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          update public.plan_entries set
            occasion = case when v_changes ? 'occasion'
              then v_changes ->> 'occasion' else occasion end,
            tentative = coalesce((v_changes ->> 'tentative')::boolean, tentative),
            items = coalesce(v_changes -> 'items', items),
            status = coalesce(v_changes ->> 'status', status),
            proposal = null,
            version = version + 1,
            updated_at = now()
          where id = v_entry_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      else
        update public.plan_entries set proposal = null, updated_at = now()
        where id = v_entry_id;
        v_result := jsonb_build_object('result', 'applied');
      end if;
    elsif v_kind = 'delete_plan_entry' then
      if not found then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        update public.plan_entries
        set deleted_at = coalesce(deleted_at, now()), updated_at = now()
        where id = v_entry_id;
        v_result := jsonb_build_object('result', 'applied');
      end if;
    else
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
    end if;
  exception
    when check_violation or invalid_text_representation then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;

  insert into public.applied_operations (op_id, owner_id, garment_id, kind, result)
  values (v_op_id, v_uid, v_entry_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;

revoke all on function public.apply_plan_operation(jsonb) from public, anon;
grant execute on function public.apply_plan_operation(jsonb) to authenticated;
