#!/usr/bin/env bash
# Prepara a IA local da build Web (correr antes de `flutter build web`):
# - web/models/: os modelos (a PWA serve-os da própria origem; o browser não
#   aceita o GitHub por causa do CORS);
# - web/ort/: o onnxruntime-web (só WASM), do pacote npm com a integridade
#   confirmada, para não depender de um CDN de terceiros.
# Nada disto vai no repositório (.gitignore).
# Confirma o sha256 de cada ficheiro, igual ao de lib/features/local_ai/
# domain/local_model.dart.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p web/models web/ort

fetch() {
  local file=$1 url=$2 sha=$3
  if [[ -f web/models/$file ]] && echo "$sha  web/models/$file" | sha256sum -c --quiet; then
    echo "$file: já está"; return
  fi
  curl -fsSL -o "web/models/$file.part" "$url"
  echo "$sha  web/models/$file.part" | sha256sum -c --quiet
  mv "web/models/$file.part" "web/models/$file"
  echo "$file: ok"
}

fetch u2netp.onnx \
  https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx \
  309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8

# onnxruntime-web: tem de ser a versão de ortWebVersion em
# lib/features/local_ai/data/ort_loader_web.dart.
ORT_VERSION=1.22.0
ORT_SHA512=Ud/+EBo6mhuaQWt/OjaOk0iNWjXqJoeeMFr6xQEERZdIZH2OWpGzuujz7lfuOBjUa6TEE/sc4nb7Da5dNL34fg==
if [[ -f web/ort/VERSION && $(cat web/ort/VERSION) == "$ORT_VERSION" ]]; then
  echo "onnxruntime-web $ORT_VERSION: já está"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/ort.tgz" \
    "https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-$ORT_VERSION.tgz"
  got=$(openssl dgst -sha512 -binary "$tmp/ort.tgz" | openssl base64 -A)
  [[ $got == "$ORT_SHA512" ]] || { echo "onnxruntime-web: integridade falhou" >&2; exit 1; }
  tar xzf "$tmp/ort.tgz" -C "$tmp" \
    package/dist/ort.wasm.min.js \
    package/dist/ort-wasm-simd-threaded.wasm \
    package/dist/ort-wasm-simd-threaded.mjs
  cp "$tmp"/package/dist/* web/ort/
  echo "$ORT_VERSION" > web/ort/VERSION
  echo "onnxruntime-web $ORT_VERSION: ok"
fi
