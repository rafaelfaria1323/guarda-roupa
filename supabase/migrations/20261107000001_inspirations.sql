-- Inspirações (incremento 4; docs/features/inspiracoes-e-estilo.md).
--
-- Uma inspiração é uma referência (título e/ou link) com etiquetas que o
-- utilizador confirmou: paleta, formalidade, padrões, texturas e ocasiões.
-- Não é posse: não referencia nem cria peças. O link é só guardado; o
-- servidor não o abre nem o interpreta. Sem imagens nesta versão.
-- Eliminar marca deleted_at (sai da sincronização).
--
-- Escritas só por apply_style_operation(op), idempotente por op_id
-- (applied_operations; garment_id = id da entidade de estilo).

-- Lista JSON de ids distintos, todos de [allowed], até [max].
create function public.jsonb_id_set_valid(arr jsonb, allowed text[], max int)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(arr) = 'array'
    and jsonb_array_length(arr) <= max
    and coalesce((
      select bool_and(jsonb_typeof(x) = 'string' and (x #>> '{}') = any (allowed))
        and count(*) = count(distinct x)
      from jsonb_array_elements(arr) as x
    ), true);
$$;

-- Paleta: RGB distintos (0xRRGGBB), até 8.
create function public.inspiration_palette_valid(palette jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(palette) = 'array'
    and jsonb_array_length(palette) <= 8
    and coalesce((
      select bool_and(
          jsonb_typeof(c) = 'number'
          and (c #>> '{}')::numeric = trunc((c #>> '{}')::numeric)
          and (c #>> '{}')::numeric between 0 and 16777215)
        and count(*) = count(distinct c)
      from jsonb_array_elements(palette) as c
    ), true);
$$;

create table public.inspirations (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  title text check (char_length(title) between 1 and 120),
  -- Só http(s), sem espaços.
  source_url text check (
    char_length(source_url) <= 2048 and source_url ~ '^https?://[^\s/?#]+[^\s]*$'
  ),
  notes text check (char_length(notes) between 1 and 1000),
  palette jsonb not null default '[]'
    check (public.inspiration_palette_valid(palette)),
  formality text check (formality in ('relaxed', 'smart_casual', 'dressy')),
  patterns jsonb not null default '[]' check (public.jsonb_id_set_valid(patterns,
    array['plain', 'stripes', 'checks', 'dots', 'floral', 'print', 'other'], 7)),
  textures jsonb not null default '[]' check (public.jsonb_id_set_valid(textures,
    array['smooth', 'ribbed', 'knit', 'textured', 'fuzzy'], 5)),
  occasions jsonb not null default '[]'
    check (public.garment_occasions_valid(occasions)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  -- Uma inspiração sem título nem link não identifica nada.
  constraint inspirations_title_or_link check (title is not null or source_url is not null)
);

create index inspirations_owner_idx on public.inspirations (owner_id)
  where deleted_at is null;

alter table public.inspirations enable row level security;

create policy inspirations_select_own on public.inspirations
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

revoke all on public.inspirations from anon, authenticated;
grant select on public.inspirations to authenticated;

alter publication powersync add table public.inspirations;

-- op = { op_id, entity_id, kind, data }
--
-- create_inspiration: { title?, source_url?, notes?, palette?, formality?,
--                       patterns?, textures?, occasions? }
-- edit_inspiration:   os mesmos campos; só os presentes mudam (último a
--                     escrever ganha, campo a campo); null apaga.
-- delete_inspiration: {}  (repetir é inofensivo)
create function public.apply_style_operation(op jsonb)
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

  select * into v_row from public.inspirations where id = v_id for update;

  begin
    if found and v_row.owner_id <> v_uid then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
    elsif v_kind = 'create_inspiration' then
      if found then
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
      if not found or v_row.deleted_at is not null then
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
    elsif v_kind = 'delete_inspiration' then
      if not found then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        update public.inspirations
        set deleted_at = coalesce(deleted_at, now()), updated_at = now()
        where id = v_id;
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
  values (v_op_id, v_uid, v_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;

revoke all on function public.apply_style_operation(jsonb) from public, anon;
grant execute on function public.apply_style_operation(jsonb) to authenticated;
