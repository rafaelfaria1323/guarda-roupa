-- Imagem e proporções das inspirações (incremento 4;
-- docs/features/inspiracoes-e-estilo.md).
--
-- - image: uma imagem própria ou autorizada (o utilizador confirma), com o
--   mesmo formato e pipeline das fotos das peças: JPEG processado no
--   cliente (1600 px + miniatura 320 px, sem metadados) no bucket privado
--   garment-photos, em {uid}/{image_id}/main.jpg|thumb.jpg. O bucket guarda
--   todas as imagens privadas do utilizador; as políticas por pasta já
--   cobrem estes ficheiros. A imagem não é analisada.
-- - proportions: etiquetas de silhueta confirmadas pelo utilizador.
--
-- Novas operações em apply_style_operation:
-- set_inspiration_image:    { image: { id, width, height, bytes, thumb_bytes, sha256 } }
--                           (os ficheiros têm de estar já no Storage; troca a atual)
-- remove_inspiration_image: { photo_id }  (só se ainda for a imagem atual)
-- create_inspiration/edit_inspiration aceitam também proportions.

alter table public.inspirations
  add column image jsonb
    check (image is null or public.garment_photos_valid(jsonb_build_array(image))),
  add column proportions jsonb not null default '[]'
    check (public.jsonb_id_set_valid(proportions, array['fitted_top_relaxed_bottom',
      'relaxed_top_fitted_bottom', 'all_fitted', 'all_relaxed', 'long_layer',
      'cropped_top'], 6));

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
  v_image jsonb;
  v_image_id uuid;
  v_prefix text;
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
    if v_kind in ('create_inspiration', 'edit_inspiration', 'delete_inspiration',
        'set_inspiration_image', 'remove_inspiration_image') then
      select * into v_row from public.inspirations where id = v_id for update;
      v_found := found;
      if v_found and v_row.owner_id <> v_uid then
        v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
      elsif v_kind = 'create_inspiration' then
        if v_found then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'already_exists');
        else
          insert into public.inspirations (id, owner_id, title, source_url, notes,
            palette, formality, patterns, textures, occasions, proportions)
          values (v_id, v_uid, v_data ->> 'title', v_data ->> 'source_url',
            v_data ->> 'notes',
            coalesce(v_data -> 'palette', '[]'::jsonb), v_data ->> 'formality',
            coalesce(v_data -> 'patterns', '[]'::jsonb),
            coalesce(v_data -> 'textures', '[]'::jsonb),
            coalesce(v_data -> 'occasions', '[]'::jsonb),
            coalesce(v_data -> 'proportions', '[]'::jsonb));
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
            proportions = case when v_data ? 'proportions'
              then coalesce(v_data -> 'proportions', '[]'::jsonb) else proportions end,
            updated_at = now()
          where id = v_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      elsif v_kind = 'set_inspiration_image' then
        v_image := v_data -> 'image';
        begin
          v_image_id := (v_image ->> 'id')::uuid;
        exception when invalid_text_representation then
          v_image_id := null;
        end;
        v_prefix := v_uid::text || '/' || v_image_id::text || '/';
        if not v_found or v_row.deleted_at is not null then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        elsif v_image_id is null
          or not public.garment_photos_valid(jsonb_build_array(v_image)) then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'invalid');
        elsif v_row.image ->> 'id' = v_image_id::text then
          v_result := jsonb_build_object('result', 'applied'); -- já ligada
        elsif (
          select count(*) from storage.objects
          where bucket_id = 'garment-photos'
            and name in (v_prefix || 'main.jpg', v_prefix || 'thumb.jpg')
        ) < 2 then
          -- Como nas peças: nunca ligar uma imagem sem ficheiros.
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'missing_file');
        else
          update public.inspirations set
            image = jsonb_build_object(
              'id', v_image_id::text,
              'width', v_image -> 'width',
              'height', v_image -> 'height',
              'bytes', v_image -> 'bytes',
              'thumb_bytes', v_image -> 'thumb_bytes',
              'sha256', v_image -> 'sha256'),
            updated_at = now()
          where id = v_id;
          v_result := jsonb_build_object('result', 'applied');
        end if;
      elsif v_kind = 'remove_inspiration_image' then
        if not v_found then
          v_result := jsonb_build_object('result', 'rejected', 'reason', 'not_found');
        else
          -- Só tira a imagem que o cliente viu: um pedido atrasado não apaga
          -- uma imagem mais recente.
          update public.inspirations set image = null, updated_at = now()
          where id = v_id and image ->> 'id' = v_data ->> 'photo_id';
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
