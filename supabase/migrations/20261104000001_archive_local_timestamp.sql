-- Arquivar passa a guardar o momento local enviado pela app.
--
-- Antes, o servidor usava now(). Se a peça fosse arquivada e desarquivada
-- offline antes de sincronizar, o desarquivar levava o archived_at local,
-- que nunca coincidia com o do servidor: ficava em conflito e a peça
-- continuava arquivada. Com o mesmo valor dos dois lados, o compare-and-set
-- do desarquivar funciona.

-- Aplica uma operação de domínio sobre uma peça do utilizador autenticado.
--
-- op = {
--   "op_id": uuid, "garment_id": uuid,
--   "kind": "create" | "edit" | "set_availability" | "archive"
--         | "unarchive" | "delete",
--   "data": { ... conforme o tipo ... }
-- }
--
-- create:           { category, name?, brand?, notes?, colors?, created_at }
-- edit:             { changes: { <campo>: { from, to } } }   (merge por campo)
-- set_availability: { from, to }
-- archive:          { archived_at? }  (momento local; sem ele, now())
-- unarchive:        { archived_at }   (o arquivo que o utilizador viu)
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
