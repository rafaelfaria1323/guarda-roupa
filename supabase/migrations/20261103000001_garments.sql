-- Fundação: allowlist (P-16), peças, idempotência e regras do ADR-008.
--
-- O cliente só LÊ diretamente (via PowerSync). Todas as escritas passam por
-- public.apply_garment_operation(op), que aplica as regras de conflito do
-- ADR-008 e é idempotente por op_id.

-- ---------------------------------------------------------------------------
-- Allowlist (P-16): só emails registados aqui podem entrar e ter dados.
-- ---------------------------------------------------------------------------

create table public.allowed_users (
  email text primary key check (email = lower(email)),
  created_at timestamptz not null default now()
);

alter table public.allowed_users enable row level security;
-- Sem policies: nenhum cliente lê ou escreve. Gerir pelo SQL Editor.
revoke all on public.allowed_users from anon, authenticated;

create function public.is_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.allowed_users
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.is_allowed() from public;
grant execute on function public.is_allowed() to authenticated;

-- Hook de Auth "Before User Created": impede criar contas fora da allowlist.
-- Ativar em Authentication > Hooks (ver docs/guias/08-poc-sincronizacao.md).
create function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.allowed_users
    where email = lower(coalesce(event -> 'user' ->> 'email', ''))
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', 'Esta conta não tem acesso à aplicação.'
    )
  );
end;
$$;

revoke all on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- Peças
-- ---------------------------------------------------------------------------

create function public.garment_colors_valid(colors jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(colors) = 'array'
    and jsonb_array_length(colors) <= 10
    and coalesce((
      select bool_and(
        jsonb_typeof(c -> 'rgb') = 'number'
        and (c ->> 'rgb')::numeric = trunc((c ->> 'rgb')::numeric)
        and (c ->> 'rgb')::numeric between 0 and 16777215
        and jsonb_typeof(c -> 'proportion') = 'number'
        and (c ->> 'proportion')::numeric > 0
        and (c ->> 'proportion')::numeric <= 1
        and jsonb_typeof(c -> 'confirmed') = 'boolean'
      )
      from jsonb_array_elements(colors) as c
    ), true)
    and coalesce((
      select sum((c ->> 'proportion')::numeric)
      from jsonb_array_elements(colors) as c
    ), 0) <= 1.000001;
$$;

create table public.garments (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  category text not null check (category in (
    't_shirt', 'shirt', 'polo', 'top', 'sweater', 'sweatshirt', 'cardigan',
    'trousers', 'jeans', 'shorts', 'skirt', 'dress', 'jumpsuit',
    'jacket', 'blazer', 'coat', 'raincoat',
    'sneakers', 'shoes', 'boots', 'sandals', 'accessory', 'other'
  )),
  name text check (char_length(name) between 1 and 80),
  brand text check (char_length(brand) between 1 and 60),
  notes text check (char_length(notes) between 1 and 1000),
  colors jsonb not null default '[]' check (public.garment_colors_valid(colors)),
  availability text not null default 'available'
    check (availability in ('available', 'drying', 'washing', 'needs_cleaning')),
  archived_at timestamptz,
  created_at timestamptz not null,
  -- Controlados pelo servidor (trigger): nunca pelo relógio do telemóvel.
  updated_at timestamptz not null default now(),
  version bigint not null default 1,
  -- Tombstone (ADR-008): peça eliminada não ressuscita.
  deleted_at timestamptz
);

create index garments_owner_idx on public.garments (owner_id) where deleted_at is null;

alter table public.garments enable row level security;

create policy garments_select_own on public.garments
  for select to authenticated
  using (owner_id = auth.uid() and public.is_allowed());

-- Só leitura direta; as escritas passam pela função de operações.
revoke all on public.garments from anon, authenticated;
grant select on public.garments to authenticated;

create function public.garments_bump_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := old.id;
  new.owner_id := old.owner_id;
  new.created_at := old.created_at;
  new.version := old.version + 1;
  new.updated_at := now();
  return new;
end;
$$;

create trigger garments_bump_version
  before update on public.garments
  for each row execute function public.garments_bump_version();

-- ---------------------------------------------------------------------------
-- Idempotência (ADR-008): cada op_id é aplicado uma única vez.
-- ---------------------------------------------------------------------------

create table public.applied_operations (
  op_id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  garment_id uuid not null,
  kind text not null,
  result jsonb not null,
  applied_at timestamptz not null default now()
);

alter table public.applied_operations enable row level security;
revoke all on public.applied_operations from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Operações
-- ---------------------------------------------------------------------------

-- Quanto maior, menos disponível. Ordem conservadora do ADR-008.
create function public.availability_caution(value text)
returns int
language sql
immutable
set search_path = ''
as $$
  select case value
    when 'available' then 0
    when 'drying' then 1
    when 'washing' then 2
    when 'needs_cleaning' then 3
  end;
$$;

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
-- unarchive:        { archived_at }   (o arquivo que o utilizador viu)
--
-- Devolve { result: applied | merged | conflict | rejected,
--           reason?, conflicts?: [{ field, local, remote }] }.
-- Repetir o mesmo op_id devolve o resultado original sem novos efeitos.
create function public.apply_garment_operation(op jsonb)
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
      update public.garments set archived_at = now() where id = v_garment_id;
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

-- ---------------------------------------------------------------------------
-- Replicação para o PowerSync (só a tabela de peças).
-- ---------------------------------------------------------------------------

create publication powersync for table public.garments;
