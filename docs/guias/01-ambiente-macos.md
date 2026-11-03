# Guia 01 — Preparar macOS, Flutter e Android

Quando: incrementos 0–1. Responsável pelas instalações/permissões: tu. O responsável pela implementação prepara o projeto e a compatibilidade das dependências.

**Este dossier não é o repositório Flutter. Não executar os comandos dentro desta pasta de Markdown esperando encontrar uma app.**

## 1. Verificar o que já existe

1. Abrir Spotlight com `Command + Espaço`, escrever Terminal e abrir.
2. Executar:

```bash
flutter --version
dart --version
flutter doctor -v
```

3. Se Flutter existir, registar versão/canal e corrigir apenas os problemas relevantes. Não reinstalar só por seguir este guia.
4. Se faltar, abrir https://docs.flutter.dev/install/manual e escolher macOS.
5. Em menu Apple > Acerca deste Mac, verificar Apple Silicon ou Intel. Selecionar o arquivo stable correspondente.
6. Descarregar e extrair. No Finder, abrir a pasta pessoal, criar `Developer` se necessário e mover a pasta `flutter` para lá, apenas se esse destino estiver livre.
7. Abrir o ficheiro de configuração do shell usado. Para zsh com login, por exemplo:

```bash
nano "$HOME/.zprofile"
```

8. Acrescentar uma única vez, ajustando ao caminho efetivo:

```bash
export PATH="$HOME/Developer/flutter/bin:$PATH"
```

9. Em nano, guardar com `Control + O`, Enter, sair com `Control + X`. Fechar e reabrir o Terminal.
10. Repetir `flutter --version` e `flutter doctor -v`.

Resultado: Flutter/Dart acessíveis sem reinstalar uma instalação válida. Se usares outro shell, seguir a secção respetiva da documentação, não editar um ficheiro que ele não lê.

## 2. Android Studio e SDK

1. Se ainda não existir, abrir https://developer.android.com/studio, descarregar para o teu Mac e instalar.
2. Abrir Android Studio e concluir o setup inicial.
3. No ecrã de boas-vindas, **More Actions > SDK Manager**. Num projeto aberto: **Tools > SDK Manager**.
4. Em **SDK Platforms**, instalar a versão compatível com o Flutter escolhido. A documentação consultada refere API 36; voltar a confirmar na implementação.
5. Em **SDK Tools**, garantir Platform-Tools, Build-Tools, Command-line Tools e Android Emulator quando for usado.
6. Aplicar e aceitar licenças no ambiente local.
7. No Terminal:

```bash
flutter doctor --android-licenses
flutter doctor -v
```

8. Resolver apenas os bloqueios Android/Web. Um aviso sobre Xcode não bloqueia estes targets iniciais.

Resultado: Android toolchain reconhecida. Se faltar Java/SDK, usar os caminhos/JDK documentados para essa versão; não alterar variáveis globalmente ao acaso.

## 3. Dispositivo de execução

### Emulador

1. Android Studio > **Device Manager**.
2. **Create Virtual Device** ou botão `+`.
3. Escolher telefone e imagem compatível: ARM em Apple Silicon ou imagem apropriada para Intel.
4. Descarregar imagem se necessário, concluir e iniciar pelo botão de reprodução.
5. Executar:

```bash
flutter devices
```

### Android físico

1. Em Definições > Acerca do telefone, ativar opções de programador pelo procedimento do fabricante.
2. Ativar depuração USB nas opções de programador.
3. Ligar por cabo de dados e autorizar apenas o teu Mac no pedido apresentado.
4. Repetir `flutter devices`.

Resultado: copiar o ID real. `emulator-5554` é apenas um exemplo, não uma constante universal.

## 4. Browser

Ter Chrome para desenvolvimento/automação Chromium. Se faltar, instalar a partir do site oficial e confirmar que surge em `flutter devices`.

Safari no Mac não substitui os testes da PWA instalada no iPhone.

## 5. Bootstrap futuro — só quando autorizado no roadmap

Parar se ainda não estiver definido onde ficará o código ou se já existir um projeto no destino. Não criar outra cópia por cima.

Exemplo de diretório e comando; substituir `pt.exemplo` pelo namespace decidido:

```bash
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
flutter create --platforms=android,web --org pt.exemplo wardrobe_app
cd "$HOME/Developer/wardrobe_app"
flutter run -d chrome --web-port 7357
```

Este comando só cria a base Flutter, não as features deste dossier. O responsável pela implementação adiciona dependências incrementalmente, migrações, auth, media e PWA.

Resultado esperado nesse momento: app base acessível em `http://localhost:7357`. Não confundir isto com demonstração do produto.

## Problemas comuns

| Problema | Ação |
|---|---|
| `command not found` | Verificar caminho efetivo e shell, reabrir Terminal |
| Dispositivo não aparece | Verificar cabo, autorização e emulador iniciado |
| SDK/licenças em falta | Voltar ao SDK Manager e ao doctor |
| Diretório de projeto já existe | Inspecionar e reutilizar; não sobrescrever |
| Versões incompatíveis | Registar e resolver compatibilidade antes de instalar mais packages |

Fontes: [registo](../fontes.md). Próximo guia quando P-01 estiver aprovado: [Supabase](02-supabase-projeto-e-storage.md).
