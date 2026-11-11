#!/usr/bin/env bash
# Build completa da PWA (build/web), igual à que o workflow "PWA" publica no
# Cloudflare Pages. Corre no Mac ou na CI:
#   tool/web/build_pwa.sh
# - ficheiros do PowerSync Web (sqlite3.wasm e workers), não versionados;
# - modelos e onnxruntime-web da IA local (tool/models/fetch_models.sh);
# - só a configuração pública de config/public.json;
# - CanvasKit servido pela própria origem (sem CDN da Google), para a app
#   abrir sem depender de terceiros.
set -euo pipefail
cd "$(dirname "$0")/../.."

flutter pub get --enforce-lockfile
dart run powersync:setup_web
tool/models/fetch_models.sh
flutter build web --release \
  --dart-define-from-file=config/public.json \
  --dart-define=BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || echo local) $(date -u +%Y-%m-%dT%H:%MZ)" \
  --no-web-resources-cdn \
  --no-wasm-dry-run

# O service worker da app (lembretes) em vez do do Flutter, que hoje só se
# desregista; o carregador do Flutter continua a registá-lo pelo mesmo nome.
cp web/push_worker.js build/web/flutter_service_worker.js

# Nada de segredos no que vai ser publicado: nem chaves secretas novas nem
# JWT antigos (o prefixo "sb_secret_" sozinho aparece no código do Supabase).
if grep -rlE 'sb_secret_[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' build/web >/dev/null; then
  echo "build/web contém algo parecido com uma chave secreta" >&2
  exit 1
fi
for f in index.html flutter_service_worker.js sqlite3.wasm main.dart.js manifest.json _headers models/u2netp.onnx ort/ort.wasm.min.js; do
  [[ -f build/web/$f ]] || { echo "falta build/web/$f" >&2; exit 1; }
done
ls build/web/powersync_*.worker.js >/dev/null
echo "build/web pronto ($(du -sh build/web | cut -f1))"
