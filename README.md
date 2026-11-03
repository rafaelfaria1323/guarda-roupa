# Guarda-roupa

Aplicação pessoal de gestão de guarda-roupa: peças, conjuntos, utilização, lavandaria, meteorologia, motor de combinações e planeamento semanal.

**Estado:** esqueleto da aplicação (navegação, tema, PT-PT, CI). Funcionalidades ainda por implementar — ver [roadmap](docs/roadmap.md).

- Plataformas: Android + PWA (iPhone), com Flutter
- Dados: local-first, com sincronização entre dispositivos via Supabase
- Idioma: português de Portugal

## Documentação

O dossier de planeamento está em [`docs/`](docs/README.md). Começar pelo [índice](docs/README.md).


## Desenvolvimento

Requer Flutter **3.47.9** (stable). Instalação no Mac: [guia 01](docs/guias/01-ambiente-macos.md).

```bash
flutter pub get
flutter run -d chrome      # PWA
flutter run -d android     # Android
flutter test
flutter analyze
```

## CI

Cada PR corre em paralelo: links da documentação, formatação/análise, testes, build Web e build Android.
Os testes são divididos automaticamente em shards de ~100 testes (`tool/ci/test_shards.py`): 300 testes → 3 shards.
Alterações só a documentação não correm os jobs Flutter.
