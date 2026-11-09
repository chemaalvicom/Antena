#!/usr/bin/env bash
# Descarga WireGuardKit (wireguard-apple, licencia MIT) en Vendor/ y compila su parte
# en Go como biblioteca estática para iPhone (Vendor/wg-go/libwg-go.a).
# Se ejecuta en macOS antes de "xcodegen generate". Necesita Go y Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WG="$VENDOR/wireguard-apple"
OUT="$VENDOR/wg-go"
WORK="$VENDOR/.wg-build"
# Versión fijada de wireguard-apple (la última publicada en el repositorio oficial).
WG_COMMIT="${WG_COMMIT:-2fec12a6e1f6e3460b6ee483aa00ad29cddadab1}"
MIN_IOS="${MIN_IOS:-17.0}"

mkdir -p "$VENDOR" "$OUT" "$WORK"

if [ ! -d "$WG/.git" ]; then
  git clone https://github.com/WireGuard/wireguard-apple "$WG"
fi
git -C "$WG" fetch --depth 1 origin "$WG_COMMIT" 2>/dev/null || true
git -C "$WG" checkout -q "$WG_COMMIT"
# El Package.swift declara swift-tools-version 5.3 pero usa .iOS(.v15)/.macOS(.v12),
# que los Xcode actuales solo aceptan a partir de 5.5.
sed -i '' -E '1s/swift-tools-version:[0-9.]+/swift-tools-version:5.5/' "$WG/Package.swift" 2>/dev/null \
  || sed -i -E '1s/swift-tools-version:[0-9.]+/swift-tools-version:5.5/' "$WG/Package.swift"
head -1 "$WG/Package.swift"

# Copia de GOROOT con el parche de WireGuard: los temporizadores cuentan el tiempo
# en reposo del iPhone (si el parche no aplica en esta versión de Go, se sigue sin él).
REAL_GOROOT="$(go env GOROOT)"
GOROOT_COPY="$WORK/goroot"
if [ ! -f "$GOROOT_COPY/.prepared" ]; then
  rm -rf "$GOROOT_COPY"
  mkdir -p "$GOROOT_COPY"
  rsync -a --delete --exclude=pkg/obj/go-build "$REAL_GOROOT/" "$GOROOT_COPY/"
  # Primero en seco: o se aplica entero o no se toca nada (medio parche rompe el enlazado).
  if cat "$WG"/Sources/WireGuardKitGo/goruntime-*.diff | patch -p1 -f -N -r- --dry-run -d "$GOROOT_COPY" >/dev/null; then
    cat "$WG"/Sources/WireGuardKitGo/goruntime-*.diff | patch -p1 -f -N -r- -d "$GOROOT_COPY"
    echo "Parche de runtime aplicado"
  else
    echo "::warning::El parche de runtime de Go no aplica en $(go version); se compila sin él"
  fi
  touch "$GOROOT_COPY/.prepared"
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"

cd "$WG/Sources/WireGuardKitGo"
env GOROOT="$GOROOT_COPY" GOTOOLCHAIN=local \
    CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
    CC="$CLANG" \
    CGO_CFLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=$MIN_IOS" \
    CGO_LDFLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=$MIN_IOS" \
    "$GOROOT_COPY/bin/go" build -ldflags=-w -trimpath -o "$OUT/libwg-go.a" -buildmode c-archive
rm -f "$OUT/libwg-go.h"

ls -lh "$OUT/libwg-go.a"
