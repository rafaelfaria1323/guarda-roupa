-- Testes de comportamento da migração de peças (ADR-008 + P-16).
-- Correr com: tool/db/test_migrations.sh
--
-- Cada operação corre numa instrução própria (\gset) e só depois se
-- verifica o estado: uma subquery na mesma instrução veria o snapshot
-- anterior à operação.
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'eu@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'outra@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
insert into public.allowed_users (email) values ('eu@example.com'), ('outra@example.com');

create function pg_temp.as_user(sub text, email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', sub, 'email', email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.op(op_id text, kind text, data jsonb,
  garment text default '10000000-0000-0000-0000-000000000001') returns jsonb
language sql as $$
  select public.apply_garment_operation(jsonb_build_object(
    'op_id', op_id, 'garment_id', garment, 'kind', kind, 'data', data));
$$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

\set G '10000000-0000-0000-0000-000000000001'

-- ------------------------------------------------------------------ P-16
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
select pg_temp.op('20000000-0000-0000-0000-000000000001', 'create', '{"category":"t_shirt"}') as r \gset
select pg_temp.check('conta fora da allowlist é rejeitada', :'r'::jsonb ->> 'reason' = 'unauthorized');
select pg_temp.check('e não cria nada', (select count(*) = 0 from public.garments));
rollback;

select pg_temp.check('hook bloqueia criação de conta não autorizada',
  public.hook_before_user_created('{"user":{"email":"intrusa@example.com"}}') ? 'error');
select pg_temp.check('hook permite email da allowlist (sem distinguir maiúsculas)',
  public.hook_before_user_created('{"user":{"email":"EU@example.com"}}') = '{}'::jsonb);

-- --------------------------------------------------------- criação e RLS
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');

select pg_temp.op('30000000-0000-0000-0000-000000000001', 'create',
  '{"category":"t_shirt","name":"  Branca ","created_at":"2026-11-03T10:00:00Z",
    "colors":[{"rgb":16777215,"proportion":0.9,"confirmed":true}]}') as r \gset
select pg_temp.check('cria peça', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('nome normalizado, versão 1, dono = utilizador',
  (select name = 'Branca' and version = 1 and owner_id = auth.uid() from public.garments));

select pg_temp.op('30000000-0000-0000-0000-000000000001', 'create', '{"category":"shirt"}') as r \gset
select pg_temp.check('repetir o op_id devolve o resultado original', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('e não duplica nem altera',
  (select count(*) = 1 and bool_and(category = 't_shirt') from public.garments));

select pg_temp.op('30000000-0000-0000-0000-000000000002', 'create', '{"category":"meia"}',
  '10000000-0000-0000-0000-000000000099') as r \gset
select pg_temp.check('rejeita categoria inválida', :'r'::jsonb ->> 'reason' = 'invalid');

select pg_temp.op('30000000-0000-0000-0000-000000000003', 'create',
  '{"category":"shirt","colors":[{"rgb":0,"proportion":0.7,"confirmed":false},
    {"rgb":1,"proportion":0.4,"confirmed":false}]}',
  '10000000-0000-0000-0000-000000000098') as r \gset
select pg_temp.check('rejeita cores acima de 100%', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.check('operações rejeitadas não criam peças', (select count(*) = 1 from public.garments));

do $$ begin
  insert into public.garments (id, owner_id, category, created_at)
  values (gen_random_uuid(), auth.uid(), 'shirt', now());
  raise exception 'FALHOU: escrita direta deveria ser negada';
exception when insufficient_privilege then
  raise notice 'ok - escrita direta na tabela é negada';
end $$;
commit;

-- -------------------------------------------------- isolamento entre contas
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'outra@example.com');
select pg_temp.check('outra conta não vê a peça', (select count(*) = 0 from public.garments));
select pg_temp.op('40000000-0000-0000-0000-000000000001', 'archive', '{}') as r \gset
select pg_temp.check('outra conta não consegue alterar a peça', :'r'::jsonb ->> 'reason' = 'not_found');
select pg_temp.op('30000000-0000-0000-0000-000000000001', 'archive', '{}') as r \gset
select pg_temp.check('outra conta não reutiliza op_id alheio', :'r'::jsonb ->> 'reason' = 'unauthorized');
rollback;
select pg_temp.check('a peça continua por arquivar',
  (select archived_at is null from public.garments where id = :'G'));

-- --------------------------------------------------------- merge por campo
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');

select pg_temp.op('50000000-0000-0000-0000-000000000001', 'edit',
  '{"changes":{"name":{"from":"Branca","to":"Branca lisa"}}}') as r \gset
select pg_temp.check('A altera o nome', :'r'::jsonb ->> 'result' = 'applied');

-- B tinha a versão antiga: muda o nome (conflito) e a marca (sem conflito).
select pg_temp.op('50000000-0000-0000-0000-000000000002', 'edit',
  '{"changes":{"name":{"from":"Branca","to":"Branca básica"},
               "brand":{"from":null,"to":"Marca X"}}}') as r \gset
select pg_temp.check('B: resultado merged com conflito no nome',
  :'r'::jsonb ->> 'result' = 'merged'
  and :'r'::jsonb -> 'conflicts' -> 0 ->> 'field' = 'name'
  and :'r'::jsonb -> 'conflicts' -> 0 ->> 'local' = 'Branca básica'
  and :'r'::jsonb -> 'conflicts' -> 0 ->> 'remote' = 'Branca lisa');
select pg_temp.check('servidor fica com o nome de A e a marca de B (versão 3)',
  (select name = 'Branca lisa' and brand = 'Marca X' and version = 3 from public.garments));

select pg_temp.op('50000000-0000-0000-0000-000000000003', 'edit',
  '{"changes":{"name":{"from":"Outro","to":"Mais outro"}}}') as r \gset
select pg_temp.check('conflito total', :'r'::jsonb ->> 'result' = 'conflict');
select pg_temp.check('conflito total não altera dados nem versão',
  (select name = 'Branca lisa' and version = 3 from public.garments));

select pg_temp.op('50000000-0000-0000-0000-000000000004', 'edit',
  '{"changes":{"owner_id":{"from":null,"to":"x"}}}') as r \gset
select pg_temp.check('editar campo não permitido é rejeitado', :'r'::jsonb ->> 'reason' = 'invalid');

select pg_temp.op('50000000-0000-0000-0000-000000000005', 'edit',
  '{"changes":{"category":{"from":"t_shirt","to":"meia"}}}') as r \gset
select pg_temp.check('editar para categoria inválida é rejeitado', :'r'::jsonb ->> 'reason' = 'invalid');
select pg_temp.check('e não altera a categoria', (select category = 't_shirt' from public.garments));
commit;

-- ---------------------------------------------------------- disponibilidade
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');

select pg_temp.op('60000000-0000-0000-0000-000000000001', 'set_availability',
  '{"from":"available","to":"needs_cleaning"}') as r \gset
select pg_temp.check('A marca precisa de limpeza', :'r'::jsonb ->> 'result' = 'applied');

select pg_temp.op('60000000-0000-0000-0000-000000000002', 'set_availability',
  '{"from":"available","to":"drying"}') as r \gset
select pg_temp.check('B (base antiga) marca a secar: conflito', :'r'::jsonb ->> 'result' = 'conflict');
select pg_temp.check('prevalece needs_cleaning', (select availability = 'needs_cleaning' from public.garments));

select pg_temp.op('60000000-0000-0000-0000-000000000003', 'set_availability',
  '{"from":"washing","to":"available"}') as r \gset
select pg_temp.check('voltar a disponível com base antiga é conflito', :'r'::jsonb ->> 'result' = 'conflict');
select pg_temp.check('e não fica disponível', (select availability = 'needs_cleaning' from public.garments));

select pg_temp.op('60000000-0000-0000-0000-000000000004', 'set_availability',
  '{"from":"needs_cleaning","to":"available"}') as r \gset
select pg_temp.check('com a base atual, voltar a disponível aplica',
  :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('fica disponível', (select availability = 'available' from public.garments));

select pg_temp.op('60000000-0000-0000-0000-000000000005', 'set_availability',
  '{"from":"drying","to":"washing"}') as r \gset
select pg_temp.check('estado mais conservador aplica mesmo com base antiga',
  :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('fica a lavar', (select availability = 'washing' from public.garments));

select pg_temp.op('60000000-0000-0000-0000-000000000006', 'set_availability',
  '{"from":"washing","to":"limpa"}') as r \gset
select pg_temp.check('estado desconhecido é rejeitado', :'r'::jsonb ->> 'reason' = 'invalid');
commit;

-- ------------------------------------------------------ arquivo e tombstone
begin;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'eu@example.com');

select pg_temp.op('70000000-0000-0000-0000-000000000001', 'archive', '{}') as r \gset
select archived_at as archived_at from public.garments \gset
select pg_temp.check('arquivar', :'r'::jsonb ->> 'result' = 'applied' and :'archived_at' <> '');

select pg_temp.op('70000000-0000-0000-0000-000000000002', 'archive', '{}') as r \gset
select pg_temp.check('arquivar de novo é idempotente e mantém a data',
  (select archived_at = :'archived_at'::timestamptz from public.garments));

select pg_temp.op('70000000-0000-0000-0000-000000000003', 'unarchive',
  '{"archived_at":"2020-01-01T00:00:00Z"}') as r \gset
select pg_temp.check('desarquivar com base desatualizada é conflito', :'r'::jsonb ->> 'result' = 'conflict');
select pg_temp.check('e continua arquivada', (select archived_at is not null from public.garments));

select pg_temp.op('70000000-0000-0000-0000-000000000004', 'unarchive',
  jsonb_build_object('archived_at', :'archived_at'::timestamptz)) as r \gset
select pg_temp.check('desarquivar com a base certa aplica', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('fica desarquivada', (select archived_at is null from public.garments));

select pg_temp.op('70000000-0000-0000-0000-000000000005', 'delete', '{}') as r \gset
select pg_temp.check('eliminar', :'r'::jsonb ->> 'result' = 'applied');
select pg_temp.check('fica tombstone, não desaparece do servidor',
  (select count(*) = 1 and bool_and(deleted_at is not null) from public.garments));

select pg_temp.op('70000000-0000-0000-0000-000000000006', 'edit',
  '{"changes":{"name":{"from":"Branca lisa","to":"Nova"}}}') as r \gset
select pg_temp.check('edição offline posterior é rejeitada (deleted)', :'r'::jsonb ->> 'reason' = 'deleted');
select pg_temp.check('e não ressuscita nem altera', (select deleted_at is not null and name = 'Branca lisa' from public.garments));

select pg_temp.op('70000000-0000-0000-0000-000000000007', 'create', '{"category":"t_shirt"}') as r \gset
select pg_temp.check('recriar com o mesmo id é rejeitado', :'r'::jsonb ->> 'reason' = 'deleted');
commit;

\echo 'Todos os testes SQL passaram.'
