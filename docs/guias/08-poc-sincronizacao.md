# Guia 08 — Preparar o servidor para a POC de sincronização

Quando: incremento 1, depois de P-01/P-02/P-03/P-04/P-16. Pré-requisito: projeto Supabase criado ([guia 02](02-supabase-projeto-e-storage.md), passos 1 e 2).

Tu executas os passos no dashboard e guardas as passwords no teu gestor. Não envies passwords nem secrets no chat. No fim, envia **só** o URL da instância PowerSync.

## 1. Aplicar o schema (automático, pela CI)

As migrações de `supabase/migrations/` são aplicadas pelo workflow [`supabase.yml`](../../.github/workflows/supabase.yml) depois de a CI passar na `main`. Em cada PR que mexa em migrações, o job "Migrações a aplicar (dry-run)" mostra o que vai ser aplicado. Configuração, uma só vez:

1. Supabase > projeto `zeibzbepuexeudzyrqzq` > **Connect** > separador **Session pooler** (porta 5432). Copiar o URI `postgresql://postgres.zeibzbepuexeudzyrqzq:[YOUR-PASSWORD]@...pooler.supabase.com:5432/postgres` e trocar `[YOUR-PASSWORD]` pela password da base. Se a password tiver caracteres como `@`, `:`, `/` ou `#`, usa uma só com letras e números (ou faz reset em **Project Settings** > **Database**).
2. GitHub > `rafaelfaria1323/guarda-roupa` > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**: nome `SUPABASE_DB_URL`, valor o URI do passo 1.

   Não é preciso access token: o CLI liga diretamente à base. A password já dá acesso total à base, por isso guarda-a só aí e no teu gestor de passwords.
3. **Só se já aplicaste alguma migração à mão** (SQL Editor), regista-a como aplicada para não correr duas vezes. No teu terminal, na pasta do repo:

   ```bash
   supabase link --project-ref zeibzbepuexeudzyrqzq
   supabase migration repair --status applied 20261103000001
   ```

   Repete o `repair` para cada ficheiro que aplicaste à mão (o número é o início do nome). `supabase migration list` mostra o estado local vs remoto.
4. GitHub > **Actions** > **Supabase** > **Run workflow** (branch `main`). O passo "Migrações pendentes" lista o que vai aplicar.
5. Confirmar em **Table Editor** que existem `garments`, `allowed_users` e `applied_operations`, todas com **RLS enabled**.

Se o workflow falhar, não alteres o SQL à mão: envia o link do run (o log não contém a password).

## 2. Autorizar a tua conta (P-16)

No SQL Editor, numa query nova, com o email da tua conta Google em minúsculas:

```sql
insert into public.allowed_users (email) values ('o-teu-email@gmail.com');
```

Opcional: acrescentar um segundo email para a conta de experiência dos testes E2E.

## 3. Bloquear contas não autorizadas no registo

1. Supabase > **Authentication** > **Hooks**.
2. **Add hook** > **Before User Created** > tipo **Postgres**.
3. Schema `public`, função `hook_before_user_created`.
4. Guardar.

Mesmo sem este hook, uma conta fora da allowlist não consegue ler nem escrever dados. O hook impede que a conta chegue sequer a ser criada.

## 4. Role de replicação para o PowerSync

No SQL Editor, numa query nova. Gera a password no teu gestor de passwords e substitui `PASSWORD_FORTE`. **Não guardes esta query** com a password.

```sql
create role powersync_role with replication bypassrls login password 'PASSWORD_FORTE';
grant usage on schema public to powersync_role;
grant select on public.garments to powersync_role;
```

O role só pode ler `garments`. Não tem acesso à allowlist nem às operações.

## 5. Criar a instância PowerSync (plano Free)

1. Abrir https://dashboard.powersync.com e criar conta, sem cartão.
2. Criar um projeto/instância **Free**, numa região europeia se existir.
3. **Database connection**: tipo PostgreSQL/Supabase.
   - Host, porta e nome da base: Supabase > **Connect** > *Direct connection* (ou *Session pooler* se o direto exigir IPv6).
   - Utilizador `powersync_role` e a password do passo 4.
   - SSL: `verify-full`, se pedido.
   - Testar a ligação e guardar.
4. **Client auth**: ativar **Use Supabase Auth** (o PowerSync valida o JWT da sessão Supabase). Se pedir o JWT secret/JWKS, seguir as instruções da própria página para Supabase.
5. **Sync Streams**: colar o conteúdo de [`powersync/sync-streams.yaml`](../../powersync/sync-streams.yaml), validar e fazer deploy.
6. Copiar o **URL da instância** (formato `https://<id>.powersync.journeyapps.com`) e envia-mo. É configuração pública.

Se a página pedir cartão ou plano pago, parar e avisar ([custos](../custos-e-limitacoes.md)).

## 6. Google OAuth

Seguir o [guia 03](03-login-e-configuracao.md), secção 2, com estes valores:

| Campo | Valor |
|---|---|
| Authorized JavaScript origins | `http://localhost:7357` |
| Authorized redirect URIs (Google) | o callback mostrado no provider Google do Supabase (`https://zeibzbepuexeudzyrqzq.supabase.co/auth/v1/callback`) |
| Supabase > URL Configuration > Redirect URLs | `http://localhost:7357/**` e `pt.rafaelfaria.guarda_roupa://login-callback` |

O Client Secret fica **só** no Supabase.

## Resultado esperado

- Schema aplicado, com RLS em todas as tabelas.
- A tua conta está na allowlist e o hook está ativo.
- PowerSync ligado, com as Sync Streams em deploy.
- Google configurado no Supabase.

Envia: o URL da instância PowerSync e a confirmação de cada passo, ou o erro exato onde paraste.
