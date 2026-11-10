-- Testes dos lembretes (claim_due_reminders e afins).
-- Correr com: tool/db/test_migrations.sh
\set ON_ERROR_STOP on

insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'eu@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'intrusa@example.com');
insert into public.allowed_users (email) values ('eu@example.com');

create function pg_temp.as_user(sub text, email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', sub, 'email', email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FALHOU: %', label; end if;
  raise notice 'ok - %', label;
end $$;

create function pg_temp.fails(label text, statement text) returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    raise notice 'ok - %', label;
    return;
  end;
  raise exception 'FALHOU: % (não falhou)', label;
end $$;

\set A '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set G1 '10000000-0000-0000-0000-000000000001'
\set G2 '10000000-0000-0000-0000-000000000002'
\set E1 'e0000000-0000-0000-0000-000000000001'
\set E2 'e0000000-0000-0000-0000-000000000002'

select token as tok from private.reminder_cron \gset

-- Utilizador: aparelho, horas e textos.
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select public.apply_garment_operation(jsonb_build_object(
  'op_id', '20000000-0000-0000-0000-000000000001', 'garment_id', :'G1', 'kind', 'create',
  'data', '{"category":"t_shirt"}'::jsonb));
select public.apply_garment_operation(jsonb_build_object(
  'op_id', '20000000-0000-0000-0000-000000000002', 'garment_id', :'G2', 'kind', 'create',
  'data', '{"category":"jeans"}'::jsonb));
select public.save_push_subscription('https://push.example/a1',
  repeat('p', 87), repeat('a', 22));
select public.set_reminder_settings('21:30', '20:00', 'Europe/Lisbon');
select pg_temp.fails('fuso inválido',
  $q$select public.set_reminder_settings('21:30', null, 'Lua/Mar')$q$);
select pg_temp.check('vê as próprias definições',
  (select count(*) = 1 from public.reminder_settings));
select pg_temp.fails('não lê os aparelhos', 'select * from public.push_subscriptions');
select pg_temp.fails('sem o token não há lembretes',
  $q$select * from public.claim_due_reminders('x')$q$);
commit;

begin;
select pg_temp.as_user(:'C', 'intrusa@example.com');
select pg_temp.fails('fora da allowlist não guarda aparelho',
  $q$select public.save_push_subscription('https://push.example/c', repeat('p', 87), repeat('a', 22))$q$);
commit;

-- Datas no futuro: `set_day_summaries` apaga resumos com mais de 2 dias,
-- e com datas fixas no passado o teste deixava de funcionar sozinho.
-- Plano: 7 (texto escrito pela app, versão certa) e 8 de novembro.
insert into public.plan_entries (id, owner_id, day, items, status, version)
values
  (:'E1', :'A', '2099-11-07',
    jsonb_build_array(jsonb_build_object('garment_id', :'G1', 'role', 'main_top'),
      jsonb_build_object('garment_id', :'G2', 'role', 'bottom')), 'accepted', 2),
  (:'E2', :'A', '2099-11-08',
    jsonb_build_array(jsonb_build_object('garment_id', :'G1', 'role', 'main_top')),
    'accepted', 1);

begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select public.set_day_summaries(jsonb_build_array(
  jsonb_build_object('day', '2099-11-07', 'plan_version', 2,
    'wear_body', 'Vestiste a t-shirt e as calças?',
    'eve_body', 'Amanhã: t-shirt + calças. Leva também: guarda-chuva.'),
  jsonb_build_object('day', '2099-11-08', 'plan_version', 1,
    'wear_body', 'Velho', 'eve_body', 'Velho')));
commit;
-- O plano de dia 8 mudou depois do texto.
update public.plan_entries set version = 2 where id = :'E2';

-- Antes da hora: nada.
select pg_temp.check('antes das 20:00 nada sai',
  (select count(*) = 0 from public.claim_due_reminders(:'tok', '2099-11-06 19:55+00')));

-- Lisboa em novembro = UTC. 20:05: véspera de dia 7, com o texto da app.
create temp table r1 as
  select * from public.claim_due_reminders(:'tok', '2099-11-06 20:05+00');
select pg_temp.check('véspera com o texto da app',
  (select count(*) = 1 and bool_and(kind = 'eve' and day = '2099-11-07'
      and body = 'Amanhã: t-shirt + calças. Leva também: guarda-chuva.'
      and url = '/planeador'
      and subscriptions -> 0 ->> 'endpoint' = 'https://push.example/a1')
   from r1));
select pg_temp.check('nunca sai duas vezes',
  (select count(*) = 0 from public.claim_due_reminders(:'tok', '2099-11-06 20:10+00')));

-- 21:35 de dia 6: sem plano e nada registado.
create temp table r2 as
  select * from public.claim_due_reminders(:'tok', '2099-11-06 21:35+00');
select pg_temp.check('sem plano pergunta o que vestiste',
  (select count(*) = 1 and bool_and(kind = 'wear_check'
      and body = 'Ainda não registaste o que vestiste hoje.' and url = '/vesti')
   from r2));

-- Véspera de dia 8 (às 20:00 de dia 7): plano mudou, texto genérico.
create temp table r4 as
  select * from public.claim_due_reminders(:'tok', '2099-11-07 20:01+00');
select pg_temp.check('texto desatualizado dá lugar ao genérico',
  (select count(*) = 1 and bool_and(body like 'Já tens roupa planeada%')
   from r4 where kind = 'eve' and day = '2099-11-08'));

-- Dia 7, 21:31: com plano e texto; abre o "Vesti hoje" com as peças.
create temp table r3 as
  select * from public.claim_due_reminders(:'tok', '2099-11-07 21:31+00');
select pg_temp.check('"Vestiste isto?" com as peças e a entrada',
  (select count(*) = 1 and bool_and(body = 'Vestiste a t-shirt e as calças?'
      and url = '/vesti?pecas=' || :'G1' || ',' || :'G2' || '&plano=' || :'E1')
   from r3 where kind = 'wear_check'));

-- Dia 8: já registado, não pergunta; dia 9 sem plano, sem véspera.
insert into public.wear_events (id, owner_id, worn_on, garment_ids)
values ('f0000000-0000-0000-0000-000000000001', :'A', '2099-11-08',
  jsonb_build_array(:'G1'));
select pg_temp.check('já registado: não pergunta; sem plano: sem véspera',
  (select count(*) = 0 from public.claim_due_reminders(:'tok', '2099-11-08 21:40+00'))
  and (select count(*) = 0 from public.claim_due_reminders(:'tok', '2099-11-08 20:05+00')));

-- Passadas 2 horas já não sai (o cron esteve parado).
select pg_temp.check('fora da janela não sai',
  (select count(*) = 0 from public.claim_due_reminders(:'tok', '2099-11-09 23:45+00')));
select pg_temp.check('janela não passa da meia-noite',
  public.reminder_due('2099-11-09 23:10', '23:00')
  and not public.reminder_due('2099-11-10 00:30', '23:00'));

-- Aparelho desaparecido.
select public.drop_push_subscriptions(:'tok', array['https://push.example/a1']);
select pg_temp.check('aparelho removido',
  (select count(*) = 0 from public.push_subscriptions));

-- Definições desligadas e aparelho removido pelo próprio.
begin;
select pg_temp.as_user(:'A', 'eu@example.com');
select public.save_push_subscription('https://push.example/a2', repeat('p', 87), repeat('a', 22));
select public.remove_push_subscription('https://push.example/a2');
commit;
select pg_temp.check('o próprio remove o aparelho',
  (select count(*) = 0 from public.push_subscriptions));
