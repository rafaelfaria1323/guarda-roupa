-- Conjuntos guardados (incremento 4; docs/features/conjuntos-e-ocasioes.md).
--
-- Um conjunto referencia peças físicas e o papel de cada uma nesse conjunto
-- (items: [{garment_id, role}], pela ordem das camadas). Não é um plano nem
-- uma utilização: editar um conjunto não altera nada do que foi usado.
-- Eliminar marca deleted_at (sai da sincronização). Uma peça que deixa de
-- estar ativa não apaga o conjunto.
--
-- Escritas só por apply_outfit_operation(op), idempotente por op_id
-- (applied_operations; garment_id = id do conjunto).

create function public.outfit_items_valid(items jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(items) = 'array'
    and jsonb_array_length(items) between 1 and 20
    and coalesce((
      select bool_and(
          jsonb_typeof(i) = 'object'
          and (i ->> 'garment_id') ~ '^[0-9a-fA-F-]{36}$'
          and (i ->> 'role') in ('main_top', 'mid_layer', 'outer_layer',
            'bottom', 'one_piece', 'footwear', 'accessory')
          and (select count(*) from jsonb_object_keys(i)) = 2)
        and count(*) = count(distinct i ->> 'garment_id')
        -- Papéis que só existem uma vez num conjunto.
        and count(*) filter (where i ->> 'role' = 'main_top') <= 1
        and count(*) filter (where i ->> 'role' = 'bottom') <= 1
        and count(*) filter (where i ->> 'role' = 'one_piece') <= 1
        and count(*) filter (where i ->> 'role' = 'footwear') <= 1
      from jsonb_array_elements(items) as i
    ), false);
$$;

create table public.outfits (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text check (char_length(name) between 1 and 120),
  occasions jsonb not null default '[]'
    check (public.garment_occasions_valid(occasions)),
  items jsonb not null check (public.outfit_items_valid(items)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index outfits_owner_idx on public.outfits (owner_id)
  where deleted_at is null;

alter table public.outfits enable row level security;

create policy outfits_select_own on public.outfits
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

revoke all on public.outfits from anon, authenticated;
grant select on public.outfits to authenticated;

alter publication powersync add table public.outfits;

-- Peças de items que são do utilizador e não foram eliminadas (arquivadas
-- contam: um conjunto antigo pode ser editado).
create function public.outfit_garments_known(uid uuid, items jsonb)
returns boolean
language sql
stable
set search_path = ''
as $$
  select count(*) = jsonb_array_length(items)
  from public.garments g
  where g.owner_id = uid and g.deleted_at is null
    and g.id::text in (select i ->> 'garment_id' from jsonb_array_elements(items) as i);
$$;

-- op = { op_id, outfit_id, kind, data }
--
-- create_outfit: { items, name?, occasions? }
-- edit_outfit:   { items?, name?, occasions? }  só os campos presentes
--                mudam (último a escrever ganha, campo a campo); name null
--                apaga o nome.
-- delete_outfit: {}  (repetir é inofensivo)
create function public.apply_outfit_operation(op jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op_id uuid;
  v_outfit_id uuid;
  v_kind text := op ->> 'kind';
  v_data jsonb := coalesce(op -> 'data', '{}'::jsonb);
  v_existing public.applied_operations;
  v_row public.outfits;
  v_result jsonb;
  v_items jsonb;
begin
  if v_uid is null or not public.is_allowed() then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
  end if;

  begin
    v_op_id := (op ->> 'op_id')::uuid;
    v_outfit_id := (op ->> 'outfit_id')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;
  if v_op_id is null or v_outfit_id is null or jsonb_typeof(v_data) <> 'object' then
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

  select * into v_row from public.outfits where id = v_outfit_id for update;

  begin
    if found and v_row.owner_id <> v_uid then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
    elsif v_kind = 'create_outfit' then
      v_items := v_data -> 'items';
      if found then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
      elsif v_items is null or not public.outfit_items_valid(v_items) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      elsif not public.outfit_garments_known(v_uid, v_items) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        insert into public.outfits (id, owner_id, name, occasions, items)
        values (v_outfit_id, v_uid, v_data ->> 'name',
          coalesce(v_data -> 'occasions', '[]'::jsonb), v_items);
        v_result := jsonb_build_object('result', 'applied');
      end if;
    elsif v_kind = 'edit_outfit' then
      v_items := v_data -> 'items';
      if not found or v_row.deleted_at is not null then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif v_items is not null and not public.outfit_items_valid(v_items) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      elsif v_items is not null and not public.outfit_garments_known(v_uid, v_items) then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        update public.outfits set
          name = case when v_data ? 'name' then v_data ->> 'name' else name end,
          occasions = case when v_data ? 'occasions'
            then coalesce(v_data -> 'occasions', '[]'::jsonb) else occasions end,
          items = coalesce(v_items, items),
          updated_at = now()
        where id = v_outfit_id;
        v_result := jsonb_build_object('result', 'applied');
      end if;
    elsif v_kind = 'delete_outfit' then
      if not found then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      else
        update public.outfits
        set deleted_at = coalesce(deleted_at, now()), updated_at = now()
        where id = v_outfit_id;
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
  values (v_op_id, v_uid, v_outfit_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;

revoke all on function public.apply_outfit_operation(jsonb) from public, anon;
grant execute on function public.apply_outfit_operation(jsonb) to authenticated;
