-- Preferências de estilo explícitas (incremento 4;
-- docs/features/inspiracoes-e-estilo.md).
--
-- Uma preferência diz "gosto" ou "evito" de um assunto (cor, padrão,
-- textura, formalidade ou uma combinação como "base neutra"), opcionalmente
-- só em certas ocasiões (contexto; vazio = sempre). Pode nascer de uma
-- inspiração (origem). Não é posse e não autoriza sugerir peças que não
-- existem: no motor é só uma componente da pontuação.
--
-- Escritas por apply_style_operation, que passa a tratar também
-- create_preference, edit_preference e delete_preference.

create function public.style_preference_value_valid(subject text, value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case subject
    when 'color' then case when value ~ '^[0-9]{1,8}$'
      then value::bigint <= 16777215 else false end
    when 'pattern' then value in ('plain', 'stripes', 'checks', 'dots', 'floral', 'print', 'other')
    when 'texture' then value in ('smooth', 'ribbed', 'knit', 'textured', 'fuzzy')
    when 'formality' then value in ('relaxed', 'smart_casual', 'dressy')
    when 'combo' then value in ('neutral_base', 'single_accent', 'tonal')
    else false
  end;
$$;

create table public.style_preferences (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  subject text not null,
  value text not null,
  stance text not null check (stance in ('like', 'avoid')),
  occasions jsonb not null default '[]'
    check (public.garment_occasions_valid(occasions)),
  -- Origem; a inspiração pode entretanto ter sido eliminada.
  inspiration_id uuid references public.inspirations (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint style_preferences_value check (public.style_preference_value_valid(subject, value))
);

create index style_preferences_owner_idx on public.style_preferences (owner_id)
  where deleted_at is null;

alter table public.style_preferences enable row level security;

create policy style_preferences_select_own on public.style_preferences
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

revoke all on public.style_preferences from anon, authenticated;
grant select on public.style_preferences to authenticated;

alter publication powersync add table public.style_preferences;

-- op = { op_id, entity_id, kind, data }
--
-- Inspirações (20261107000001):
--   create_inspiration, edit_inspiration, delete_inspiration.
-- Preferências:
--   create_preference: { subject, value, stance, occasions?, inspiration_id? }
--   edit_preference:   { value?, stance?, occasions? }  só os presentes
--                      mudam; o assunto e a origem não mudam.
--   delete_preference: {}  (repetir é inofensivo)
create or replace function public.apply_style_operation(op jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op_id uuid;
  v_id uuid;
  v_kind text := op ->> 'kind';
  v_data jsonb := coalesce(op -> 'data', '{}'::jsonb);
  v_existing public.applied_operations;
  v_row public.inspirations;
  v_pref public.style_preferences;
  v_found boolean;
  v_source uuid;
  v_result jsonb;
begin
  if v_uid is null or not public.is_allowed() then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
  end if;

  begin
    v_op_id := (op ->> 'op_id')::uuid;
    v_id := (op ->> 'entity_id')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;
  if v_op_id is null or v_id is null or jsonb_typeof(v_data) <> 'object' then
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
    if v_kind in ('create_inspiration', 'edit_inspiration', 'delete_inspiration') then
      select * into v_row from public.inspirations where id = v_id for update;
      v_found := found;
      if v_found and v_row.owner_id <> v_uid then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif v_kind = 'create_inspiration' then
        if v_found then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
        else
          insert into public.inspirations (id, owner_id, title, source_url, notes,
            palette, formality, patterns, textures, occasions)
          values (v_id, v_uid, v_data ->> 'title', v_data ->> 'source_url',
            v_data ->> 'notes',
            coalesce(v_data -> 'palette', '[]'::jsonb), v_data ->> 'formality',
            coalesce(v_data -> 'patterns', '[]'::jsonb),
            coalesce(v_data -> 'textures', '[]'::jsonb),
            coalesce(v_data -> 'occasions', '[]'::jsonb));
          v_result := jsonb_build_object('result', 'applied');
        end if;
      elsif v_kind = 'edit_inspiration' then
        if not v_found or v_row.deleted_at is not null then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          update public.inspirations set
            title = case when v_data ? 'title' then v_data ->> 'title' else title end,
            source_url = case when v_data ? 'source_url'
              then v_data ->> 'source_url' else source_url end,
            notes = case when v_data ? 'notes' then v_data ->> 'notes' else notes end,
            palette = case when v_data ? 'palette'
              then coalesce(v_data -> 'palette', '[]'::jsonb) else palette end,
            formality = case when v_data ? 'formality'
              then v_data ->> 'formality' else formality end,
            patterns = case when v_data ? 'patterns'
              then coalesce(v_data -> 'patterns', '[]'::jsonb) else patterns end,
            textures = case when v_data ? 'textures'
              then coalesce(v_data -> 'textures', '[]'::jsonb) else textures end,
            occasions = case when v_data ? 'occasions'
              then coalesce(v_data -> 'occasions', '[]'::jsonb) else occasions end,
            updated_at = now()
          where id = v_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      else -- delete_inspiration
        if not v_found then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          update public.inspirations
          set deleted_at = coalesce(deleted_at, now()), updated_at = now()
          where id = v_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      end if;

    elsif v_kind in ('create_preference', 'edit_preference', 'delete_preference') then
      select * into v_pref from public.style_preferences where id = v_id for update;
      v_found := found;
      if v_found and v_pref.owner_id <> v_uid then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif v_kind = 'create_preference' then
        v_source := (v_data ->> 'inspiration_id')::uuid;
        if v_found then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
        elsif v_source is not null and not exists (
          select 1 from public.inspirations where id = v_source and owner_id = v_uid
        ) then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          insert into public.style_preferences (id, owner_id, subject, value, stance,
            occasions, inspiration_id)
          values (v_id, v_uid, v_data ->> 'subject', v_data ->> 'value',
            v_data ->> 'stance', coalesce(v_data -> 'occasions', '[]'::jsonb), v_source);
          v_result := jsonb_build_object('result', 'applied');
        end if;
      elsif v_kind = 'edit_preference' then
        if not v_found or v_pref.deleted_at is not null then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        elsif v_data ? 'subject' or v_data ? 'inspiration_id' then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
        else
          update public.style_preferences set
            value = case when v_data ? 'value' then v_data ->> 'value' else value end,
            stance = case when v_data ? 'stance' then v_data ->> 'stance' else stance end,
            occasions = case when v_data ? 'occasions'
              then coalesce(v_data -> 'occasions', '[]'::jsonb) else occasions end,
            updated_at = now()
          where id = v_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      else -- delete_preference
        if not v_found then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          update public.style_preferences
          set deleted_at = coalesce(deleted_at, now()), updated_at = now()
          where id = v_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      end if;

    else
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
    end if;
  exception
    when check_violation or not_null_violation or invalid_text_representation then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;

  insert into public.applied_operations (op_id, owner_id, garment_id, kind, result)
  values (v_op_id, v_uid, v_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;
