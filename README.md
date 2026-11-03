# Guarda-roupa

Aplicação pessoal de gestão de guarda-roupa: peças, conjuntos, utilização, lavandaria, meteorologia, motor de combinações e planeamento semanal.

**Estado:** POC de sincronização (incremento 1): login Google, base local por conta (PowerSync/SQLite) e catálogo de peças (criar, editar, disponibilidade, duplicar, arquivar, pesquisar). Fotografias e restantes funcionalidades por implementar — ver [roadmap](docs/roadmap.md).

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

Sem `POWERSYNC_URL` em `config/public.json`, a app funciona só localmente e mostra "sincronização por configurar". Ver o [guia 08](docs/guias/08-poc-sincronizacao.md).

## CI

Cada PR corre em paralelo: links da documentação, formatação/análise, testes Flutter e testes SQL (migrações Supabase num PostgreSQL 17 com stub de `auth`).
Os builds Android e Web ficam fora da CI por agora, para entregar mais depressa. Voltam quando houver distribuição.

Os testes são divididos em shards por `tool/ci/test_shards.py`. O script estima o custo de cada ficheiro e
escolhe o número de shards que minimiza o tempo total, tendo em conta o custo fixo de arranque de cada
job (só acrescenta um shard se poupar pelo menos 30 s). Depois distribui os ficheiros de forma equilibrada
(algoritmo LPT). As estimativas podem ser afinadas por variáveis de ambiente quando houver tempos reais.
Alterações só a documentação não correm os jobs Flutter.

As migrações Supabase são aplicadas pelo workflow `supabase.yml` depois de a CI passar na `main` (dry-run nos PRs). Requer os secrets `SUPABASE_ACCESS_TOKEN` e `SUPABASE_DB_PASSWORD` no GitHub; ver o [guia 08](docs/guias/08-poc-sincronizacao.md).
