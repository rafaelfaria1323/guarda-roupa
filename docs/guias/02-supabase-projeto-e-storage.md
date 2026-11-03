# Guia 02 — Criar projeto e Storage no Supabase

Quando: fundação, **se Supabase for aprovado em P-01**.

Tu crias a conta/projeto e guardas credenciais. O responsável pela implementação prepara schema, migrações, RLS e políticas de Storage. Não foram gerados scripts de base neste dossier.

## 1. Conta e projeto Free

1. Abrir https://supabase.com/dashboard.
2. Criar/entrar na tua conta e concluir verificações pedidas.
3. Se for necessário criar uma organização, escolher nome pessoal e o plano **Free**.
4. Escolher **New project** e a organização correta.
5. Preencher nome, por exemplo `wardrobe-personal`.
6. Gerar uma password de base forte no teu gestor de passwords e guardá-la lá. Não enviar em chat.
7. Escolher uma região europeia disponível adequada, verificando a localização concreta.
8. Confirmar que o resumo continua Free e criar. Se houver exigência de plano pago/cartão incompatível com o requisito, parar.
9. Aguardar inicialização e registar o nome/identificador do projeto.

Resultado: projeto vazio acessível no dashboard. Criar o projeto não implementa sincronização.

## 2. Obter apenas a configuração pública do cliente

1. No projeto, abrir o painel **Connect**.
2. Copiar **Project URL** e a **publishable key** para a configuração local da aplicação.
3. Se necessário, consultar **Settings > API Keys** para identificar o tipo de chave.
4. Não usar secret key, password da base ou `service_role` no Flutter.

As chaves novas publicáveis têm prefixo `sb_publishable_...`; as secretas `sb_secret_...` são apenas servidor. Não deduzir autorização pelo prefixo: RLS continua obrigatória.

## 3. Schema e autorização — gate de implementação

**Parar aqui se ainda não existirem migrações revistas no futuro repositório.** Não colar SQL de um exemplo de “public todos” do quickstart.

Quando existirem:

1. Abrir o projeto correto e confirmar que é o ambiente de experiência/pessoal pretendido.
2. Seguir o procedimento de migração do repositório; preferir CLI versionada/reprodutível.
3. Se a fase de POC usar Dashboard, abrir **SQL Editor > New query** e executar apenas o script revisto correspondente à versão.
4. Confirmar tabelas/constraints em **Table Editor**.
5. Confirmar RLS em todas as tabelas expostas e políticas de leitura/escrita por utilizador.
6. Demonstrar os cenários entre conta A e B antes de carregar dados pessoais.

RLS exige `select`, `insert`, `update` e `delete` coerentes, incluindo checks de propriedade e referências. Criar tabelas pelo SQL não garante automaticamente todas estas políticas.

## 4. Buckets privados

Nomes propostos que têm de coincidir com a configuração da implementação:

1. Menu **Storage > New Bucket**.
2. Nome `wardrobe-images`.
3. Deixar **Public bucket** desligado.
4. Nas opções disponíveis, limitar MIME a `image/jpeg`, `image/png`, `image/webp`.
5. Limite inicial proposto: 5 MB por imagem otimizada; confirmar o pipeline antes de o adotar. Não anunciar HEIC sem suporte.
6. Criar.
7. Repetir para `inspirations` se a feature usar bucket separado.
8. Abrir políticas de Storage e aplicar as regras revistas da implementação.

Pasta proposta: utilizador/asset/variante. A policy deve verificar propriedade real, não confiar num texto arbitrário enviado pelo cliente.

Bucket privado sozinho não substitui autorização de operações. Não ativar acesso público para “resolver” uma imagem que não aparece.

## 5. Restringir registo pessoal

Antes de expor a app, fechar P-16:

1. Escolher se só a tua identidade pode entrar ou se há registos de experiência adicionais.
2. Na secção **Authentication**, rever configuração de registo/provider com o responsável.
3. Aplicar allowlist/mecanismo de servidor escolhido e testá-lo.
4. Confirmar que uma identidade não autorizada não consegue criar/aceder a dados.

Não desativar novos utilizadores sem preparar a criação inicial da tua conta. A configuração exata depende do método de login escolhido no [guia 03](03-login-e-configuracao.md).

## 6. Se PowerSync for escolhido

Não criar um serviço adicional antes da POC. O procedimento de ligação, credenciais de replicação, regras e versões deve ser registado no resultado de P-03 **antes** de te ser pedida essa ação.

Não copiar a password PostgreSQL para o APK/PWA. A integração adicional não é uma configuração invisível já concluída por este guia.

## Resultado e problemas

Esperado após implementação: utilizador autenticado só lê/escreve os seus dados/media. Sem sessão ou com outra conta, acesso negado.

Se uma operação falhar: verificar sessão, policy e caminho; não desligar RLS como correção. Se quota/plano impedir o passo, parar e rever [custos](../custos-e-limitacoes.md).

Fontes e menus sujeitos a atualização: [registo](../fontes.md).
