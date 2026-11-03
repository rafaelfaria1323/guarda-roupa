-- Fotografias das peças (incremento 1).
--
-- - Metadados em garments.photos (JSON tipado, até 5), sincronizados pelo
--   PowerSync com o resto da peça.
-- - Ficheiros JPEG já processados no cliente (1600 px + miniatura 320 px,
--   sem metadados) num bucket privado: {uid}/{photo_id}/main.jpg|thumb.jpg.
--   Ficheiros imutáveis: uma foto nova tem sempre um id novo.
-- - attach_photo só liga a foto depois de os dois ficheiros existirem.

create function public.garment_photos_valid(photos jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(photos) = 'array'
    and jsonb_array_length(photos) <= 5
    and coalesce((
      select bool_and(
        jsonb_typeof(p) = 'object'
        and (p ->> 'id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and jsonb_typeof(p -> 'width') = 'number'
        and (p ->> 'width')::numeric = trunc((p ->> 'width')::numeric)
        and (p ->> 'width')::numeric between 1 and 4096
        and jsonb_typeof(p -> 'height') = 'number'
        and (p ->> 'height')::numeric = trunc((p ->> 'height')::numeric)
        and (p ->> 'height')::numeric between 1 and 4096
        and jsonb_typeof(p -> 'bytes') = 'number'
        and (p ->> 'bytes')::numeric = trunc((p ->> 'bytes')::numeric)
        and (p ->> 'bytes')::numeric between 1 and 5242880
        and jsonb_typeof(p -> 'thumb_bytes') = 'number'
        and (p ->> 'thumb_bytes')::numeric = trunc((p ->> 'thumb_bytes')::numeric)
        and (p ->> 'thumb_bytes')::numeric between 1 and 5242880
        and (p ->> 'sha256') ~ '^[0-9a-f]{64}$'
      )
      from jsonb_array_elements(photos) as p
    ), true);
$$;

alter table public.garments
  add column photos jsonb not null default '[]'
  check (public.garment_photos_valid(photos));

-- Bucket privado. Limite por ficheiro acima dos ~300 KB esperados, para
-- não falhar com fotos com muito detalhe.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('garment-photos', 'garment-photos', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- Cada utilizador só mexe na sua pasta. O update existe porque a app envia
-- com upsert (repetir um envio interrompido); os ficheiros não mudam de
-- conteúdo, porque cada foto nova tem id novo.
create policy garment_photos_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'garment-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_allowed()
  );

create policy garment_photos_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'garment-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_allowed()
  );

create policy garment_photos_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'garment-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_allowed()
  )
  with check (
    bucket_id = 'garment-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_allowed()
  );

create policy garment_photos_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'garment-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_allowed()
  );

-- Aplica uma operação de domínio sobre uma peça do utilizador autenticado.
--
-- op = {
--   "op_id": uuid, "garment_id": uuid,
--   "kind": "create" | "edit" | "set_availability" | "archive"
--         | "unarchive" | "delete" | "attach_photo" | "detach_photo",
--   "data": { ... conforme o tipo ... }
-- }
--
-- create:           { category, name?, brand?, notes?, colors?, created_at }
-- edit:             { changes: { <campo>: { from, to } } }   (merge por campo)
-- set_availability: { from, to }
-- archive:          { archived_at? }  (momento local; sem ele, now())
-- unarchive:        { archived_at }   (o arquivo que o utilizador viu)
-- attach_photo:     { photo: { id, width, height, bytes, thumb_bytes, sha256 } }
--                   (os ficheiros têm de estar já no Storage)
-- detach_photo:     { photo_id }
--
-- Devolve { result: applied | merged | conflict | rejected,
--           reason?, conflicts?: [{ field, local, remote }] }.
-- Repetir o mesmo op_id devolve o resultado original sem novos efeitos.
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
          id, owner_id, category, name, brand, notes, colors, created_at
        ) values (
          v_garment_id,
          v_uid,
          v_data ->> 'category',
          nullif(btrim(v_data ->> 'name'), ''),
          nullif(btrim(v_data ->> 'brand'), ''),
          nullif(btrim(v_data ->> 'notes'), ''),
          coalesce(v_data -> 'colors', '[]'::jsonb),
          coalesce((v_data ->> 'created_at')::timestamptz, now())
        );
        v_result := jsonb_build_object('result', 'applied');
      exception
        when check_violation or not_null_violation
          or invalid_text_representation or invalid_datetime_format then
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
        if v_field not in ('category', 'name', 'brand', 'notes', 'colors') then
          raise exception using errcode = '22023';
        end if;
        if (to_jsonb(v_row) -> v_field) is not distinct from coalesce(v_change -> 'from', 'null'::jsonb) then
          case v_field
            when 'category' then v_row.category := v_change ->> 'to';
            when 'name' then v_row.name := nullif(btrim(v_change ->> 'to'), '');
            when 'brand' then v_row.brand := nullif(btrim(v_change ->> 'to'), '');
            when 'notes' then v_row.notes := nullif(btrim(v_change ->> 'to'), '');
            when 'colors' then v_row.colors := coalesce(v_change -> 'to', '[]'::jsonb);
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
          colors = v_row.colors
        where id = v_garment_id
          and (category, name, brand, notes, colors)
            is distinct from (v_row.category, v_row.name, v_row.brand, v_row.notes, v_row.colors);
      end if;

      v_result := case
        when jsonb_array_length(v_conflicts) = 0 then jsonb_build_object('result', 'applied')
        when v_applied > 0 then jsonb_build_object('result', 'merged', 'conflicts', v_conflicts)
        else jsonb_build_object('result', 'conflict', 'conflicts', v_conflicts)
      end;
    exception
      when check_violation or invalid_parameter_value then
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
