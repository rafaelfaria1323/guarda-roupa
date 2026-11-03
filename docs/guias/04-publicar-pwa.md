# Guia 04 — Publicar a PWA

Quando: a partir da fundação, primeiro num ambiente de experiência. Responsável pelas contas, autorizações e escolha do alojamento: tu. O responsável pela implementação prepara e verifica o build, cache offline, callbacks e headers.

**Este dossier não contém código Flutter nem uma PWA pronta a publicar. Não executar estes passos agora como se a implementação existisse.** As condições Free de referência estão em [Custos e limitações](../custos-e-limitacoes.md).

## 1. Pré-requisitos e ponto de paragem

Antes de criar o projeto de alojamento, confirmar:

1. Existe o repositório da aplicação, num diretório diferente deste dossier.
2. O fornecedor de alojamento foi aceite; Cloudflare Pages é a recomendação, não uma conta já criada.
3. Login, policies e restrições de registo pessoal estão definidos. Esconder o botão de registo não substitui a regra no servidor.
4. O build inclui manifest, ícones, rotas, SQLite/WASM e workers necessários.
5. Existe configuração Workbox explícita e um procedimento de build completo, executado pelo responsável pela implementação. `flutter build web` por si só não comprova offline.
6. Foram definidos os URLs de experiência/produção e o que falta demonstrar em Safari, conforme P-05.

Não é necessário que a primeira publicação experimental já tenha passado todos os testes de iPhone: serve também para os executar. Não a anunciar como versão utilizável antes desse gate.

## 2. Escolher como publicar

| Caminho | Quando escolher | Consequência |
|---|---|---|
| Integração Git | Recomendado para desenvolvimento contínuo | Builds automáticos; exige preparar a toolchain Flutter no build |
| Direct Upload | Experiência manual com artefactos já construídos | Não passa depois a integração Git no mesmo projeto |
| Wrangler | Publicação por CLI; necessário para compilar/publicar Pages Functions neste fluxo | Exige Node/tooling compatível e autorização Cloudflare |

Não criar um projeto por cada caminho. Escolher primeiro. Um projeto Git também permite deploys Wrangler, mas isso não é converter o seu modo de integração. Uma eventual mudança de projeto/domínio exige tratar origin, dados locais e callbacks.

## 3. Preparar o artefacto correto

Diretório ilustrativo do futuro código: `$HOME/Developer/wardrobe_app`.

O comando Flutter base, depois de o código ler estas variáveis públicas, será semelhante a:

```bash
cd "$HOME/Developer/wardrobe_app"
flutter build web --release \
  --dart-define="SUPABASE_URL=URL_REAL_DO_PROJETO" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=CHAVE_PUBLICAVEL_REAL"
```

Substituir os placeholders localmente. Este comando **não é o procedimento completo de PWA**: falta executar a geração/pós-processamento Workbox definido no repositório. Parar se esse passo ainda não existir ou não estiver documentado.

O procedimento completo deve:

- Usar Flutter e ferramentas em versões compatíveis e fixadas.
- Gerar o bundle e a configuração pública, sem secrets.
- Gerar o service worker depois dos assets finais, incluindo o necessário para SQLite/WASM.
- Colocar os headers/rotas necessários no artefacto publicado.
- Verificar que `build/web` contém o resultado final e não apenas um build intermédio.

O responsável pela implementação fornece o comando único e verificado para este procedimento. Não inventar um `npm run` nem presumir que o ambiente Cloudflare já inclui Flutter.

Não publicar `.env`, keystores, tokens, dumps ou fotografias pessoais em `build/web`. O service worker trata assets públicos da aplicação, não faz cache indiscriminada de respostas autenticadas ou imagens privadas.

## 4. Caminho recomendado — integração Git

Só seguir com repositório e comando de build completo já existentes.

1. Abrir https://dash.cloudflare.com/ e entrar/criar conta, aceitando apenas o plano Free pretendido.
2. Abrir **Workers & Pages > Create application > Pages > Connect to Git**.
3. Escolher GitHub ou GitLab. Em GitHub, limitar a autorização ao repositório necessário quando a opção existir.
4. Selecionar o repositório, autorizar e abrir **Begin setup**.
5. Em **Project name**, escolher um nome disponível, por exemplo `wardrobe-pessoal`.
6. Em **Production branch**, escolher a branch efetiva; `main` é apenas um exemplo. A branch já deve existir no remoto.
7. Em framework, escolher **None** ou deixar sem preset, conforme a interface.
8. Em **Build command**, introduzir o comando completo fornecido pela implementação, incluindo a preparação do SDK. Não colocar apenas `flutter build web` num ambiente sem Flutter.
9. Em **Build output directory**, indicar `build/web`, relativamente à raiz de build escolhida.
10. Se a app estiver numa subpasta, indicar essa pasta em **Root directory (advanced)**; se estiver na raiz do repositório, não inventar outra.
11. Nas variáveis do build, definir apenas a configuração pública necessária. O script deve convertê-la nos `--dart-define` lidos pela app; Flutter não o faz automaticamente por terem o mesmo nome.
12. Separar produção e previews. Não dar às experiências acesso inadvertido ao guarda-roupa pessoal.
13. Escolher **Save and Deploy**, observar logs e guardar o URL HTTPS devolvido.

Resultado: deploy associado ao commit e ao URL real. Um estado “deploy concluído” prova a publicação dos ficheiros, não o funcionamento das features.

## 5. Alternativa — Direct Upload pelo dashboard

Só seguir depois do build completo local.

1. No dashboard Cloudflare, abrir **Workers & Pages > Create application**.
2. Escolher o percurso **Get started > Drag and drop your files** da secção Pages; a apresentação pode variar.
3. Definir o nome do projeto.
4. Arrastar a pasta final `build/web` ou o ZIP preparado desse conteúdo, sem acrescentar um nível de pasta errado.
5. Confirmar que `index.html` está na raiz publicada.
6. Escolher **Deploy site** e guardar o URL.

O upload pelo dashboard tem limite de 1.000 ficheiros na documentação consultada. Não confundir com os 20.000 ficheiros por site do Pages Free nem com o limite de 25 MiB por ficheiro.

O dashboard não compila a pasta `functions`. Se esse backend existir, usar o fluxo Wrangler preparado para ele, não publicar só a parte estática e declarar o importador funcional.

## 6. Alternativa por CLI — Wrangler

Pré-requisito adicional: versão Node LTS compatível com Wrangler e tooling aprovado no repositório. Verificar `node --version` e `npm --version`. Se faltarem, preparar Node a partir de https://nodejs.org/en/download, escolhendo macOS e a arquitetura real; não instalar versões aleatórias para ultrapassar um erro de build.

Os exemplos usam `npx wrangler`; preferir a versão fixada pelo projeto e aprovar qualquer instalação solicitada. Estes comandos não foram executados nesta entrega.

1. Na raiz do futuro repositório, autenticar:

```bash
cd "$HOME/Developer/wardrobe_app"
npx wrangler login
```

2. Autorizar no browser a conta Cloudflare correta.
3. Para um projeto Direct Upload novo, criar o projeto; se já existir, não o recriar:

```bash
npx wrangler pages project create wardrobe-pessoal
```

4. Responder ao pedido de branch de produção com a branch escolhida.
5. Depois do build completo, publicar:

```bash
npx wrangler pages deploy build/web --project-name wardrobe-pessoal
```

6. Usar o nome real do projeto e a branch de produção aprovada quando o comando a solicitar. Confirmar no dashboard se o resultado é produção ou preview.

Se existirem Pages Functions, o responsável prepara também a pasta/configuração respetiva e confirma no deploy que foram incluídas. Não mover credenciais de servidor para os assets Flutter.

## 7. Validar o URL e atualizar o login

1. Abrir o URL HTTPS de produção e confirmar certificado e primeira carga.
2. Rever **Supabase > Authentication > URL Configuration**, conforme o [Guia 03](03-login-e-configuracao.md).
3. Registar o callback Web exato implementado e a Site URL. Rever também as origens do cliente Google, se esse método for usado.
4. Não trocar o callback Google → Supabase pelo URL da PWA.
5. Validar carregamento direto das rotas, incluindo retorno de autenticação.
6. Confirmar resposta e MIME corretos dos ficheiros WASM, incluindo `application/wasm`, e que workers não recebem `index.html` por engano.
7. Se forem necessários COOP/COEP, testar também OAuth/popups e recursos externos. Não copiar headers sem validar o conjunto.
8. Executar primeira carga online, preparação offline e reabertura sem rede pelo [Guia 06](06-executar-validacoes.md), incluindo iPhone real.

Inicialmente, o domínio `pages.dev` evita comprar um domínio próprio. Uma mudança posterior de origin não transporta automaticamente IndexedDB ou sessões; sincronizar/exportar antes da transição.

## Recuperação

| Sintoma | Ação |
|---|---|
| Build diz que Flutter não existe | Corrigir preparação do SDK no pipeline; não assumir um preset inexistente |
| Página vazia ou assets 404 | Rever raiz publicada, base path, headers e ficheiros finais |
| Login não regressa | Comparar callbacks e origens reais com o Guia 03 |
| Funciona online, falha offline | Rever Workbox, primeira carga e cache dos workers/WASM; ainda não passou P-05 |
| Versão antiga continua aberta | Verificar estado de atualização do service worker e procedimento seguro; não apagar dados do browser |
| Ficheiro excede limite | Rever artefacto ou alojamento; não ativar plano pago sem decisão |

Não limpar armazenamento nem reinstalar a PWA como reparação genérica. Preservar dados e operações pendentes antes de qualquer ação destrutiva.

Fontes: Cloudflare Git integration e Direct Upload, Flutter FAQ e Drift Web em [Fontes](../fontes.md). Próximo procedimento: [instalação](05-instalar-android-e-pwa.md).
