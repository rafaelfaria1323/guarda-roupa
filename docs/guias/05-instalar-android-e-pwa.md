# Guia 05 — Instalar no Android e no iPhone

Quando: depois de existir um build funcional. Responsável pelos dispositivos, autorizações e guarda da chave Android: tu. O responsável pela implementação prepara assinatura, manifest, callbacks e atualizações.

A PWA é publicada automaticamente no Cloudflare Pages ([Guia 04](04-publicar-pwa.md)), em `https://guarda-roupa.pages.dev` (2026-11-04). O APK Android ainda é compilado à mão.

## 1. Android para desenvolvimento

Pré-requisitos: [ambiente Android](01-ambiente-macos.md), dispositivo autorizado e configuração de login definida.

1. Ligar o Android por USB ou iniciar o emulador.
2. Abrir Terminal no diretório real da aplicação.
3. Listar dispositivos:

```bash
cd "$HOME/Developer/wardrobe_app"
flutter devices
```

4. Copiar o ID Android real; não escrever literalmente `ID_ANDROID`.
5. Executar, substituindo também os valores públicos:

```bash
flutter run -d ID_ANDROID \
  --dart-define="SUPABASE_URL=URL_REAL_DO_PROJETO" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=CHAVE_PUBLICAVEL_REAL"
```

6. Na primeira abertura, entrar na conta de experiência e confirmar carregamento/sync.
7. Ao adicionar uma foto, conceder apenas o acesso necessário. Recusar/cancelar também deve funcionar sem criar uma peça incompleta silenciosamente.

Resultado: versão de desenvolvimento no dispositivo selecionado. Isto não é uma distribuição release assinada com a tua chave definitiva.

## 2. Preparar assinatura pessoal Android

Gate: P-15 de [Pendências](../pendencias.md). Não criar uma chave nova se já existe a chave usada para instalar versões que têm de continuar atualizáveis.

1. Confirmar o `applicationId` definitivo com o responsável pela implementação.
2. Verificar se já existe keystore e registar o certificado esperado.
3. Se for realmente a primeira chave, escolher uma pasta privada fora do repositório. Exemplo:

```bash
mkdir -p "$HOME/.wardrobe-signing"
chmod 700 "$HOME/.wardrobe-signing"
```

4. Confirmar que `wardrobe-release.jks` ainda não existe nessa pasta. Se existir, parar e identificar a sua origem.
5. Gerar a chave com o `keytool` do JDK configurado:

```bash
keytool -genkeypair -v \
  -keystore "$HOME/.wardrobe-signing/wardrobe-release.jks" \
  -storetype JKS -keyalg RSA -keysize 2048 \
  -validity 10000 -alias wardrobe
```

6. Responder localmente aos pedidos. Guardar passwords num gestor de passwords, não na linha de comando nem no chat.
7. Fazer uma cópia protegida do keystore fora do computador antes de depender dele para atualizações.

Se `keytool` não existir no PATH, consultar o JDK indicado por `flutter doctor -v` e usar o executável dessa instalação. Não instalar outro JDK sem verificar compatibilidade.

## 3. Ligar assinatura ao futuro projeto

1. O responsável pela implementação confirma que `android/key.properties` e keystores estão excluídos do Git.
2. Criar/configurar localmente `android/key.properties`, com os valores reais:

```properties
storePassword=PASSWORD_GUARDADA_LOCALMENTE
keyPassword=PASSWORD_DA_CHAVE
keyAlias=wardrobe
storeFile=CAMINHO_ABSOLUTO_DO_KEYSTORE
```

3. Substituir `storeFile` pelo caminho absoluto real. Não presumir que `~` ou `$HOME` são expandidos dentro deste ficheiro.
4. O responsável configura Gradle para carregar as propriedades e usar a assinatura release correta, conforme a versão Kotlin DSL/Groovy do projeto.
5. Remover a associação release → debug do scaffold. A ausência da chave deve bloquear o build destinado a distribuição, não assinar silenciosamente com outra.
6. Confirmar também a permissão Internet no manifest release e os deep links reais.

**`--release` não prova que o APK usa uma chave própria.** O scaffold pode continuar associado à assinatura debug até ser corretamente configurado.

## 4. Construir e instalar o APK pessoal

1. Confirmar assinatura, versão/build number e configuração pública.
2. Na raiz da aplicação:

```bash
flutter build apk --release \
  --dart-define="SUPABASE_URL=URL_REAL_DO_PROJETO" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=CHAVE_PUBLICAVEL_REAL"
```

3. Verificar o certificado do APK com `apksigner`, instalado nos Android SDK Build-Tools. Se estiver no PATH:

```bash
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

4. Se faltar no PATH, abrir Android Studio > SDK Manager, consultar **Android SDK Location** e a versão instalada de Build-Tools, e usar o caminho real `build-tools/VERSAO/apksigner`.
5. Comparar a fingerprint apresentada com a chave aprovada, não apenas com a existência de uma assinatura.
6. Confirmar o dispositivo com `adb devices` e instalar:

```bash
adb -s ID_ANDROID install -r build/app/outputs/flutter-apk/app-release.apk
```

7. Se `adb` não estiver no PATH, usar o executável de `platform-tools` no SDK identificado no passo anterior.
8. Abrir pelo ícone, autenticar e verificar catálogo, fotografias e estado de sync.

O resultado esperado do instalador é `Success`, seguido da verificação na aplicação. A instalação pessoal por APK não exige publicação paga numa loja.

Para atualizar, manter `applicationId` e identidade de assinatura compatíveis, aumentar a versão como definido pelo projeto e usar `install -r`. Executar E2E-16 para comprovar preservação e migrações.

Se aparecer `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, não desinstalar imediatamente: pode haver assinatura diferente e dados ainda não sincronizados. Preservar/exportar esses dados, identificar certificados e decidir a migração. Uma versão debug pode precisar de uma instalação de experiência separada desde o início.

## 5. Adicionar a PWA ao iPhone

Pré-requisitos: URL HTTPS real, primeira carga com Internet e procedimento offline preparado. A PWA não precisa de publicação App Store nem de conta Apple Developer paga.

Os nomes dos controlos variam com iOS e idioma. O guia Apple atual está em [Fontes](../fontes.md); a consulta direta ficou limitada por HTTP 429, pelo que se deve confirmar a apresentação no aparelho.

1. No iPhone, abrir **Safari**.
2. Abrir `https://guarda-roupa.pages.dev` (ou o endereço do resumo do workflow PWA), não o `localhost` do Mac.
3. Esperar pela primeira carga completa. Se houver erro, resolver antes de instalar.
4. Abrir **Partilhar**. Consoante a apresentação, o botão pode estar acessível pelo menu do browser.
5. Escolher **Adicionar ao ecrã principal**; percorrer a lista de ações se necessário.
6. Confirmar o nome e o endereço.
7. Se aparecer **Abrir como aplicação Web / Open as Web App**, ativar para a experiência instalada.
8. Tocar em **Adicionar**.
9. Voltar ao ecrã principal e abrir pelo novo ícone.
10. Entrar na conta e aguardar dados e fotografias necessários. Pode ser necessário autenticar novamente.
11. Confirmar, na UI implementada, preparação offline e ausência de uploads/downloads relevantes por concluir.

Não assumir que a sessão ou todos os dados locais do separador Safari são partilhados com a PWA instalada. Testar a instância aberta pelo ícone.

## 6. Primeira verificação nos dois aparelhos

1. Entrar na mesma conta de experiência no Android e na PWA instalada.
2. Criar uma peça com foto no Android e observar a chegada à PWA.
3. Editar na PWA e observar o Android.
4. Confirmar que o estado de sync distingue dados e fotografias.
5. Só depois de a primeira preparação estar completa, testar sem rede conforme o [Guia 06](06-executar-validacoes.md).

A sync ocorre ao abrir e enquanto a app está em utilização. Não esperar que uma PWA fechada continue a sincronizar permanentemente.

## Recuperação e atualizações

| Situação | Procedimento |
---|---|
| Não aparece “Adicionar ao ecrã principal” | Confirmar Safari e menu de ações; verificar restrições do dispositivo/versão |
| Ícone abre mas está sem dados | Confirmar conta, origin e sync da instância instalada |
| Sem Internet na primeira abertura | Voltar à rede e concluir preparação; não declarar offline indisponível definitivamente sem diagnóstico |
| Foto de iPhone não é aceite | Registar formato/versão e falha; não mudar a extensão de HEIC para fingir conversão |
| Atualização pede reabrir | Primeiro preservar operações pendentes; aplicar o procedimento seguro de atualização |
| Nova URL não mostra dados locais | Tratar como mudança de origin; não apagar a instalação antiga |

Não remover a PWA, limpar Safari ou desinstalar o APK para corrigir um problema sem salvaguardar dados. Backup e recuperação: [Guia 07](07-operacao-backups-e-limites.md).
