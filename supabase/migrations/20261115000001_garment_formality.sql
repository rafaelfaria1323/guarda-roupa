-- Formalidade de uma peça (2026-11-06): relaxed | smart_casual | dressy,
-- os mesmos ids da formalidade das inspirações. null = desconhecida; o
-- motor de combinações evita juntar uma peça descontraída com uma
-- arranjada e conta as preferências de formalidade.

alter table public.garments
  add column formality text
    check (formality in ('relaxed', 'smart_casual', 'dressy'));

-- Aplica uma operação de domínio sobre uma peça do utilizador autenticado.
-- Igual à de 20261104000003, com `formality` em create e edit.
create or replace function public.apply_garment_operation(op jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op_id uuid;
  v_garment_id uuid;
  v_kind text := op ->> 'kind';
  v_data jsonb := coalesce(op -> 'data', '{}'::jsonb);
  v_existing public.applied_operations;
  v_row public.garments;
  v_result jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_applied int := 0;
  v_field text;
  v_change jsonb;
  v_from text;
  v_to text;
  v_current text;
  v_photo jsonb;
  v_photo_id uuid;
  v_prefix text;
begin
  if v_uid is null or not public.is_allowed() then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
  end if;

  begin
    v_op_id := (op ->> 'op_id')::uuid;
    v_garment_id := (op ->> 'garment_id')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end;
  if v_op_id is null or v_garment_id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end if;

  -- Idempotência. O lock evita duas aplicações concorrentes do mesmo op_id.
  perform pg_advisory_xact_lock(hashtextextended(v_op_id::text, 0));
  select * into v_existing from public.applied_operations where op_id = v_op_id;
  if found then
    if v_existing.owner_id <> v_uid then
      return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized');
    end if;
    return v_existing.result;
  end if;

  select * into v_row from public.garments where id = v_garment_id for update;

  if found and v_row.owner_id <> v_uid then
    -- Não revela se a peça de outro utilizador existe.
    v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
  elsif found and v_row.deleted_at is not null then
    v_result := jsonb_build_object('result', 'rejected', 'reason', 'deleted');
  elsif v_kind = 'create' then
    if found then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
    else
      begin
        insert into public.garments (
          id, owner_id, category, name, brand, notes, colors,
          pattern, texture, warmth, rain_ok, wind_ok, formality, occasions,
          material, care, created_at
        ) values (
          v_garment_id,
          v_uid,
          v_data ->> 'category',
          nullif(btrim(v_data ->> 'name'), ''),
          nullif(btrim(v_data ->> 'brand'), ''),
          nullif(btrim(v_data ->> 'notes'), ''),
          coalesce(v_data -> 'colors', '[]'::jsonb),
          v_data ->> 'pattern',
          v_data ->> 'texture',
          v_data ->> 'warmth',
          (v_data ->> 'rain_ok')::boolean,
          (v_data ->> 'wind_ok')::boolean,
          v_data ->> 'formality',
          coalesce(v_data -> 'occasions', '[]'::jsonb),
          nullif(btrim(v_data ->> 'material'), ''),
          nullif(btrim(v_data ->> 'care'), ''),
          coalesce((v_data ->> 'created_at')::timestamptz, now())
        );
        v_result := jsonb_build_object('result', 'applied');
      exception
        when check_violation or not_null_violation
          or invalid_text_representation or invalid_datetime_format
          or invalid_parameter_value then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
      end;
    end if;
  elsif not found then
    v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
  elsif v_kind = 'edit' then
    -- Merge por campo: aplica cada campo cujo valor atual ainda é o "from"
    -- que o cliente viu; os restantes ficam como conflito (valor do servidor
    -- mantém-se e o local é devolvido para o utilizador decidir).
    begin
      for v_field, v_change in
        select key, value from jsonb_each(coalesce(v_data -> 'changes', '{}'::jsonb))
      loop
        if v_field not in ('category', 'name', 'brand', 'notes', 'colors',
            'pattern', 'texture', 'warmth', 'rain_ok', 'wind_ok', 'formality',
            'occasions', 'material', 'care') then
          raise exception using errcode = '22023';
        end if;
        if (to_jsonb(v_row) -> v_field) is not distinct from coalesce(v_change -> 'from', 'null'::jsonb) then
          case v_field
            when 'category' then v_row.category := v_change ->> 'to';
            when 'name' then v_row.name := nullif(btrim(v_change ->> 'to'), '');
            when 'brand' then v_row.brand := nullif(btrim(v_change ->> 'to'), '');
            when 'notes' then v_row.notes := nullif(btrim(v_change ->> 'to'), '');
            when 'colors' then v_row.colors := coalesce(v_change -> 'to', '[]'::jsonb);
            when 'pattern' then v_row.pattern := v_change ->> 'to';
            when 'texture' then v_row.texture := v_change ->> 'to';
            when 'warmth' then v_row.warmth := v_change ->> 'to';
            when 'rain_ok' then v_row.rain_ok := (v_change ->> 'to')::boolean;
            when 'wind_ok' then v_row.wind_ok := (v_change ->> 'to')::boolean;
            when 'formality' then v_row.formality := v_change ->> 'to';
            when 'occasions' then v_row.occasions := coalesce(v_change -> 'to', '[]'::jsonb);
            when 'material' then v_row.material := nullif(btrim(v_change ->> 'to'), '');
            when 'care' then v_row.care := nullif(btrim(v_change ->> 'to'), '');
          end case;
          v_applied := v_applied + 1;
        elsif (to_jsonb(v_row) -> v_field) is not distinct from coalesce(v_change -> 'to', 'null'::jsonb) then
          v_applied := v_applied + 1; -- já tem o valor pretendido
        else
          v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
            'field', v_field,
            'local', v_change -> 'to',
            'remote', to_jsonb(v_row) -> v_field
          ));
        end if;
      end loop;

      if v_applied > 0 then
        update public.garments set
          category = v_row.category,
          name = v_row.name,
          brand = v_row.brand,
          notes = v_row.notes,
          colors = v_row.colors,
          pattern = v_row.pattern,
          texture = v_row.texture,
          warmth = v_row.warmth,
          rain_ok = v_row.rain_ok,
          wind_ok = v_row.wind_ok,
          formality = v_row.formality,
          occasions = v_row.occasions,
          material = v_row.material,
          care = v_row.care
        where id = v_garment_id
          and (category, name, brand, notes, colors, pattern, texture, warmth,
               rain_ok, wind_ok, formality, occasions, material, care)
            is distinct from (v_row.category, v_row.name, v_row.brand,
               v_row.notes, v_row.colors, v_row.pattern, v_row.texture,
               v_row.warmth, v_row.rain_ok, v_row.wind_ok, v_row.formality,
               v_row.occasions,
               v_row.material, v_row.care);
      end if;

      v_result := case
        when jsonb_array_length(v_conflicts) = 0 then jsonb_build_object('result', 'applied')
        when v_applied > 0 then jsonb_build_object('result', 'merged', 'conflicts', v_conflicts)
        else jsonb_build_object('result', 'conflict', 'conflicts', v_conflicts)
      end;
    exception
      when check_violation or invalid_parameter_value
        or invalid_text_representation then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
    end;
  elsif v_kind = 'set_availability' then
    v_from := v_data ->> 'from';
    v_to := v_data ->> 'to';
    v_current := v_row.availability;
    if public.availability_caution(v_to) is null then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
    elsif v_current = v_to then
      v_result := jsonb_build_object('result', 'applied');
    elsif v_current is not distinct from v_from
      or public.availability_caution(v_to) > public.availability_caution(v_current) then
      -- Base atual, ou o novo estado é mais conservador: aplica.
      update public.garments set availability = v_to where id = v_garment_id;
      v_result := jsonb_build_object('result', 'applied');
    else
      -- Base desatualizada e o pedido é menos conservador (ex.: voltar a
      -- "disponível" depois de o outro dispositivo marcar "precisa de
      -- limpeza"): não se aplica sem confirmação.
      v_result := jsonb_build_object(
        'result', 'conflict',
        'conflicts', jsonb_build_array(jsonb_build_object(
          'field', 'availability', 'local', v_to, 'remote', v_current
        ))
      );
    end if;
  elsif v_kind = 'archive' then
    if v_row.archived_at is null then
      update public.garments
      set archived_at = coalesce((v_data ->> 'archived_at')::timestamptz, now())
      where id = v_garment_id;
    end if;
    v_result := jsonb_build_object('result', 'applied');
  elsif v_kind = 'unarchive' then
    if v_row.archived_at is null then
      v_result := jsonb_build_object('result', 'applied');
    elsif v_row.archived_at is not distinct from (v_data ->> 'archived_at')::timestamptz then
      update public.garments set archived_at = null where id = v_garment_id;
      v_result := jsonb_build_object('result', 'applied');
    else
      v_result := jsonb_build_object(
        'result', 'conflict',
        'conflicts', jsonb_build_array(jsonb_build_object(
          'field', 'archived_at', 'local', null, 'remote', v_row.archived_at
        ))
      );
    end if;
  elsif v_kind = 'delete' then
    update public.garments set deleted_at = now() where id = v_garment_id;
    v_result := jsonb_build_object('result', 'applied');
  elsif v_kind = 'attach_photo' then
    v_photo := v_data -> 'photo';
    begin
      v_photo_id := (v_photo ->> 'id')::uuid;
    exception when invalid_text_representation then
      v_photo_id := null;
    end;
    v_prefix := v_uid::text || '/' || v_photo_id::text || '/';
    if v_photo_id is null or not public.garment_photos_valid(jsonb_build_array(v_photo)) then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
    elsif exists (
      select 1 from jsonb_array_elements(v_row.photos) p where p ->> 'id' = v_photo_id::text
    ) then
      v_result := jsonb_build_object('result', 'applied'); -- já ligada
    elsif jsonb_array_length(v_row.photos) >= 5 then
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'too_many');
    elsif (
      select count(*) from storage.objects
      where bucket_id = 'garment-photos'
        and name in (v_prefix || 'main.jpg', v_prefix || 'thumb.jpg')
    ) < 2 then
      -- Nunca ligar uma foto cujos ficheiros não existem: o outro
      -- dispositivo ficaria com uma imagem vazia.
      v_result := jsonb_build_object('result', 'rejected', 'reason', 'missing_file');
    else
      update public.garments
      set photos = photos || jsonb_build_array(jsonb_build_object(
        'id', v_photo_id::text,
        'width', v_photo -> 'width',
        'height', v_photo -> 'height',
        'bytes', v_photo -> 'bytes',
        'thumb_bytes', v_photo -> 'thumb_bytes',
        'sha256', v_photo -> 'sha256'
      ))
      where id = v_garment_id;
      v_result := jsonb_build_object('result', 'applied');
    end if;
  elsif v_kind = 'detach_photo' then
    update public.garments
    set photos = coalesce((
      select jsonb_agg(p order by n)
      from jsonb_array_elements(photos) with ordinality as e(p, n)
      where p ->> 'id' is distinct from v_data ->> 'photo_id'
    ), '[]'::jsonb)
    where id = v_garment_id
      and exists (
        select 1 from jsonb_array_elements(photos) p
        where p ->> 'id' = v_data ->> 'photo_id'
      );
    v_result := jsonb_build_object('result', 'applied');
  else
    v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
  end if;

  insert into public.applied_operations (op_id, owner_id, garment_id, kind, result)
  values (v_op_id, v_uid, v_garment_id, coalesce(v_kind, ''), v_result);

  return v_result;
end;
$$;

revoke all on function public.apply_garment_operation(jsonb) from public, anon;
grant execute on function public.apply_garment_operation(jsonb) to authenticated;
