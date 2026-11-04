# Guarda-roupa

Aplicação pessoal de gestão de guarda-roupa: peças, conjuntos, utilização, lavandaria, meteorologia, motor de combinações e planeamento semanal.

**Estado:** POC de sincronização (incremento 1): login Google, base local por conta (PowerSync/SQLite) catálogo de peças (criar, editar, disponibilidade, duplicar, arquivar, pesquisar) e fotografias das peças (câmara/galeria, sincronizadas por Storage privado). Restantes funcionalidades por implementar — ver [roadmap](docs/roadmap.md).

- Plataformas: Android + PWA (iPhone), com Flutter
- Dados: local-first, com sincronização entre dispositivos via Supabase
- Idioma: português de Portugal

## Documentação

O dossier de planeamento está em [`docs/`](docs/README.md). Começar pelo [índice](docs/README.md).


## Desenvolvimento

Requer Flutter **3.47.9** (stable). Instalação no Mac: [guia 01](docs/guias/01-ambiente-macos.md).

```bash
flutter pub get
flutter run -d chrome --web-port 7357 --dart-define-from-file=config/public.json
flutter run -d android --dart-define-from-file=config/public.json
flutter test
flutter analyze
tool/db/test_migrations.sh   # requer PostgreSQL local
```

Na Web, o PowerSync precisa dos ficheiros WASM/worker em `web/` (não versionados). Antes do primeiro `flutter run -d chrome`:

```bash
dart run powersync:setup_web
```

A IA local opcional (Definições › IA local) precisa, na Web, do modelo e do `onnxruntime-web` em `web/models/` e `web/ort/` (também não versionados, com sha256/integridade confirmados):

```bash
tool/models/fetch_models.sh
```

A build completa da PWA (a mesma que o workflow `PWA` publica no Cloudflare Pages, [guia 04](docs/guias/04-publicar-pwa.md)) faz tudo isto:

```bash
tool/web/build_pwa.sh
```

Sem `POWERSYNC_URL` em `config/public.json`, a app funciona só localmente e mostra "sincronização por configurar". Ver o [guia 08](docs/guias/08-poc-sincronizacao.md).

## CI

Cada PR corre em paralelo: links da documentação, formatação/análise, testes Flutter e testes SQL (migrações Supabase num PostgreSQL 17 com stub de `auth`).
Os builds Android e Web ficam fora da CI por agora, para entregar mais depressa. Voltam quando houver distribuição.

Os testes são divididos em shards por `tool/ci/test_shards.py`. O script estima o custo de cada ficheiro e
escolhe o número de shards que minimiza o tempo total, tendo em conta o custo fixo de arranque de cada
job (só acrescenta um shard se poupar pelo menos 30 s). Depois distribui os ficheiros de forma equilibrada
(algoritmo LPT). As estimativas podem ser afinadas por variáveis de ambiente quando houver tempos reais.
Alterações só a documentação não correm os jobs Flutter.

As migrações Supabase são aplicadas pelo workflow `supabase.yml` depois de a CI passar na `main` (dry-run nos PRs). Requer o secret `SUPABASE_DB_URL` (URI do Session pooler) no GitHub; ver o [guia 08](docs/guias/08-poc-sincronizacao.md).
