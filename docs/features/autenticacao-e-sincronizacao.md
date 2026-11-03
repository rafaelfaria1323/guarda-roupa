# Feature — Autenticação e sincronização

Estado: sync entre Android e PWA confirmada desde o início; fornecedor/login/engine a aprovar.

## Comportamento requerido

Entrar na mesma conta, trabalhar sobre dados locais, sincronizar ao abrir, durante utilização online e ao recuperar ligação.

Não exigir execução contínua com a PWA fechada. Mostrar última sincronização, alterações pendentes, media por enviar e erros.

Um dispositivo offline não conhece alterações recentes do outro. A interface deve ser honesta sobre essa limitação.

## Backend e login

Supabase é o candidato recomendado: Auth, PostgreSQL, RLS e buckets privados.

Método de login ainda não escolhido. Google OAuth evita depender de emails de autenticação no caso inicial, mas exige configuração Google/Supabase. Email/password ou magic link precisam de entrega e recuperação reais; o SMTP padrão não é um serviço público de email de produção.

Contas partilhadas entre pessoas, vários perfis e funções de equipa não fazem parte do MVP pessoal.

## Opções de sincronização

| Opção | Vantagem | Custo/risco |
|---|---|---|
| Supabase + PowerSync Free | Menos reinvenção de sync; plano gratuito atual | Serviço adicional, quotas, integração Drift/Web e media a provar |
| Supabase + protocolo próprio | Mais controlo e menos fornecedor adicional | Outbox, cursores, conflitos, deletes e recuperação passam a ser responsabilidade da app |
| Supabase Realtime apenas | Atualizações rápidas online | Não resolve sozinho fila offline, replay ou conflitos |
| Firestore | Offline integrado em clientes suportados | Modelo/queries diferentes; fotografias Firebase exigem Blaze |
| Backend self-hosted | Controlo e software potencialmente gratuito | Alojamento, atualizações e disponibilidade não se tornam gratuitos |

**Recomendação:** executar primeiro uma POC pequena da opção estabelecida PowerSync; escolher após comprovar Android, PWA no iPhone, Drift, escrita e ficheiros. Não implementar dois motores de produção em paralelo.

Análise completa: [ADR-004](../decisoes/004-sincronizacao.md).

## Requisitos comuns às duas opções viáveis

- Escritas locais duráveis e repetição segura depois de interrupção.
- Identidade da operação e validação no servidor.
- Confirmação da mesma entrada de plano idempotente.
- Deletes/tombstones e tratamento de dispositivo muito antigo.
- Conflitos sem perda silenciosa de estados críticos.
- Upload/download de ficheiros com retomada e estado independente dos metadados.
- Respeito por propriedade e isolamento de contas.
- Migrações e reautenticação sem apagar pendências por defeito.

Não usar timestamps de clientes como ordem global. Um `bigserial` isolado também não prova ordem de commit para uma sync incremental sem perdas.

## Semântica de conflitos proposta

| Caso | Direção a validar |
|---|---|
| Edição concorrente de nome/etiqueta | Merge documentado ou revisão; evitar perda silenciosa |
| Disponível versus precisa de limpeza | Não regressar silenciosamente a “limpo”; aviso e resolução conservadora |
| Mesma entrada confirmada duas vezes | Uma utilização lógica |
| Dois usos manuais independentes | Preservar e oferecer correção quando necessário |
| Peça apagada versus editada offline | Tombstone ou conflito explícito; não ressuscitar |
| Plano editado em dois dispositivos | Versão base e proposta de resolução |

Estas políticas precisam de aprovação em P-04. O SDK de sync não escolhe automaticamente a semântica correta do produto.

## Privacidade e sessões

Chave publicável pode estar no cliente; `sb_secret_...`/`service_role` não podem. RLS deve proteger cada tabela e políticas próprias devem proteger Storage.

Definir no servidor se o registo é apenas pessoal ou aberto. Esconder o botão de registo não impede criar contas pela API.

Logout deve avisar sobre alterações pendentes e isolar a base/media locais. Não sincronizar dados da conta A para B.

## Ações do utilizador

Aprovar fornecedor/login e seguir [Supabase](../guias/02-supabase-projeto-e-storage.md) e [login](../guias/03-login-e-configuracao.md). Não partilhar passwords, client secrets, tokens ou chave privada de assinatura em chat.

## Aceitação

E2E-04, E2E-11 e E2E-14 do [plano](../plano-e2e.md): dois dispositivos, offline/retry, mesma confirmação, conflitos, eliminação antiga, imagem interrompida e isolamento.
