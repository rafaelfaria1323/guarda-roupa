# Feature — Ler fotos com o Gemini (opcional)

Estado: implementado a 2026-11-06 (pedido do utilizador: menos algoritmos próprios para manter, usando a quota grátis do Gemini). Fica **desligado** até o utilizador o ligar. Falta guardar a chave do Gemini nos secrets e experimentar com fotos reais.

## Decisão

- O Gemini é **só uma opção**. A app funciona igual sem ele: com ele desligado, sem chave no servidor, sem rede ou sem quota, segue pelo que já faz neste aparelho ([IA local](ia-local.md) e cores pela foto).
- O motor de sugestões e o planeador da semana **não mudam**: continuam no aparelho, sem custo e sem rede.
- O Gemini só **sugere**. Tudo fica por confirmar antes de guardar, e há sempre "Desfazer".

## O que faz

Ligar em **Definições › IA local › Ler fotos com o Gemini**. A opção é por aparelho.

| Onde | O que o Gemini lê | Se falhar |
|---|---|---|
| **Várias peças de uma vez** | Categoria, nome curto (pt-PT, sem marca), até 3 cores com a proporção, padrão, textura, aquecimento e formalidade | Segue pela categoria do FashionCLIP e pelas cores da foto. Sem chave, sem quota ou fora da lista, avisa uma vez e as restantes fotos seguem sem o Gemini |
| Peça: **Preencher pela foto (Gemini)** (com uma foto) | O mesmo, a partir da capa. Muda a categoria e as cores; o nome e os atributos só se estiverem vazios | Mensagem; o formulário fica como estava |
| Peça: **Ler a etiqueta (Gemini)** | Lavagem (máquina 30/40/60, à mão, lavandaria), máquina de secar, composição e outros cuidados, em pt-PT | Mensagem; a foto da etiqueta nunca se guarda |

Mais tarde: a foto ao espelho (ver o que se vestiu), com a mesma função.

## Privacidade e limites

- A foto sai do aparelho só quando o utilizador adiciona fotos ou toca num botão do Gemini, e só com a opção ligada. Não fica guardada no servidor da app.
- Na versão grátis da API, a Google pode usar o conteúdo para melhorar os produtos dela. O ecrã das Definições diz isto antes de ligar.
- Limite da app: 60 fotos por hora e 300 por dia por pessoa (`claim_photo_ai_quota`). A quota grátis do Gemini muda com o tempo e por modelo; quando acaba, a função responde "busy" e a app avisa.

## Como funciona

- **App:** `lib/features/photo_ai/`. `SupabasePhotoReader` manda a foto principal (JPEG ≤ 1600 px) em base64 para a Edge Function `describe-photo`, com a sessão. A opção guarda-se em `local_settings` (`gemini_photos`).
- **Função `describe-photo`** (`supabase/functions/describe-photo/`):
  1. Valida o pedido (tipo, base64, ≤ 1,5 MB) antes de gastar quota.
  2. Pede à base a quota (`claim_photo_ai_quota`). A base confirma a sessão e a allowlist.
  3. Chama o Gemini com a resposta presa a um esquema JSON e `temperature: 0`.
  4. Devolve só valores que a app conhece: categorias, cores de referência, padrões… O resto vem `null`.
- **Chave:** secret `GEMINI_API_KEY` no GitHub. O workflow "Supabase" passa-a aos secrets da função; sem ele, a função responde 503 e a app usa o que tem. O modelo é `gemini-flash-lite-latest` (o alias segue a versão atual) e muda-se com o secret da função `GEMINI_MODEL`, sem mexer no código.
- Os registos da função só têm o estado HTTP, nunca a foto nem a chave.

Dados em [modelo de dados](../modelo-de-dados.md#leitura-de-fotos-com-o-gemini-2026-11-06).

## Criar a chave (uma vez, o utilizador)

1. Em [Google AI Studio](https://aistudio.google.com/apikey), entrar com a conta Google e **Create API key**. Não é preciso ativar faturação: sem faturação fica no nível grátis.
2. No GitHub do repositório: **Settings › Secrets and variables › Actions › New repository secret**. Nome `GEMINI_API_KEY`, valor a chave. Não colar a chave em mais lado nenhum (chat, código, notas).
3. Correr o workflow "Supabase" (Actions › Supabase › Run workflow) ou esperar pelo próximo merge na `main`.
4. Na app: **Definições › IA local › Usar o Gemini neste aparelho**.

Para trocar ou revogar a chave: apagá-la no AI Studio e guardar a nova no mesmo secret.
