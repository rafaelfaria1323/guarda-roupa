# Guia 03 — Login, callbacks e configuração

Quando: depois de P-01/P-02. **Não criar todos os métodos de login; seguir apenas o aprovado.**

Tu autorizas contas e guardas secrets no fornecedor correto. O responsável pela implementação prepara rotas, deep links, PKCE/sessão e leitura das variáveis públicas.

## 1. URLs a preparar

| Uso | Valor |
|---|---|
| Desenvolvimento Web | `http://localhost:7357` se for o porto escolhido |
| Produção Web | URL HTTPS real devolvida pelo alojamento |
| Callback Google → Supabase | Copiar do provider Google no dashboard |
| Callback Supabase → app | Rota/deep link efetivamente implementado |

Exemplos de rotas propostas: `/auth/callback` na Web e `pt.exemplo.wardrobe://auth/callback` no Android. Não as registar como se existissem antes de a implementação confirmar os valores.

## 2. Opção Google — cliente Web

1. Abrir https://console.cloud.google.com/.
2. No seletor de projetos, criar/selecionar um projeto pessoal para a aplicação.
3. Abrir **Google Auth Platform**.
4. Em **Branding**, preencher nome, email de suporte e contacto do developer.
5. Em **Audience**, escolher a opção adequada à conta. Para conta pessoal fora de organização Workspace, normalmente **External**.
6. Se estiver em modo **Testing**, adicionar o teu email em test users.
7. Em **Data Access/Scopes**, limitar a `openid`, email e profile. Não pedir acesso ao Gmail/Drive.
8. Abrir **Clients > Create client > Web application**.
9. Dar um nome, por exemplo `Wardrobe Web`.
10. Em authorized JavaScript origins, adicionar a origem localhost escolhida e, quando existir, a origem HTTPS de produção. Origem é protocolo/host/porto, sem `/auth/callback`.
11. Noutra janela, abrir Supabase > projeto > **Authentication > Sign In / Providers > Google**. A nomenclatura pode variar; procurar o provider Google.
12. Copiar o callback mostrado, normalmente `https://PROJECT_REF.supabase.co/auth/v1/callback`.
13. No cliente Google, adicionar esse callback em **Authorized redirect URIs** e guardar.
14. Copiar Client ID e Client Secret para os campos do provider Google **no Supabase**, ativar e guardar.

Client Secret não vai para Dart, `.env` incluído no bundle, Git ou chat.

## 3. Permitir regresso à aplicação

1. Supabase > **Authentication > URL Configuration**.
2. Definir **Site URL** para a origem de produção quando existir.
3. Em **Redirect URLs**, registar callbacks exatos de desenvolvimento/produção implementados.
4. No desenvolvimento inicial, usar localhost conforme o fluxo aprovado; atualizar antes de publicar.
5. Evitar wildcards amplos em produção.

São duas configurações diferentes: Google redireciona para Supabase; Supabase redireciona para a aplicação.

## 4. Android — escolher um dos fluxos

### A. OAuth no browser com regresso por deep link

O cliente Web Google acima pode participar neste fluxo. O responsável pela implementação configura a URI no manifest Android e no SDK, valida PKCE e trata cold start/regresso.

Tu registas essa URI na allowlist Supabase quando ela estiver confirmada. Não é necessário criar um cliente Android Google apenas por existir uma app Android neste fluxo.

### B. Google Sign-In nativo

Exige configuração adicional. Só seguir se esta abordagem for escolhida:

1. Obter o `applicationId` definitivo na configuração Android do projeto.
2. Na pasta Android do futuro projeto, executar:

```bash
cd "$HOME/Developer/wardrobe_app/android"
./gradlew signingReport
```

3. Copiar SHA-1 da variante debug correta.
4. Google Auth Platform > **Clients > Create client > Android**.
5. Introduzir package name e SHA-1 e guardar.
6. Repetir para assinatura release quando for criada.
7. O responsável liga os IDs adequados ao SDK nativo e à validação no Supabase, seguindo as versões escolhidas.

Não confundir fingerprint com chave privada. Não usar só o certificado debug numa distribuição release.

## 5. Se o método escolhido for email

1. Supabase > **Authentication > Providers**: configurar apenas o método escolhido.
2. Rever **URL Configuration** e rotas reais de confirmação/recuperação.
3. Abrir a configuração SMTP na secção Authentication.
4. Para uso limitado, verificar se o endereço está autorizado na equipa e cabe no limite atual.
5. Para outros destinatários, configurar SMTP próprio aprovado, com credenciais guardadas no servidor.
6. Testar registo, expiração/recuperação e entrega antes de confiar no método.

O remetente padrão anuncia apenas 2 mensagens/hora e destinatários restritos. Não desativar proteções de conta como remendo para falta de emails.

## 6. Executar a futura app com configuração pública

Pré-requisito: o código já lê os nomes abaixo. Substituir os placeholders localmente.

```bash
cd "$HOME/Developer/wardrobe_app"
flutter run -d chrome --web-port 7357 \
  --dart-define="SUPABASE_URL=URL_REAL_DO_PROJETO" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=CHAVE_PUBLICAVEL_REAL"
```

Estes valores ficam acessíveis no cliente. Não são um mecanismo para esconder secrets.

## Resultado e recuperação

Esperado: entrar, regressar à app, fechar/reabrir com sessão coerente e sair sem misturar dados de contas.

| Erro | Verificar |
|---|---|
| Redirect mismatch | Diferença entre callback Google e retorno da app; porto, protocolo e path exatos |
| Access blocked em Testing | Email adicionado a test users e scopes corretos |
| Android não regressa | Deep link/manifest/URI real ou configuração do SDK nativo |
| Email não chega | Destinatário autorizado, SMTP, quota e spam |
| Sessão funciona mas dados negados | Policies/RLS; não trocar para secret key |

Fontes: Google OAuth, API keys e SMTP em [Fontes](../fontes.md).
