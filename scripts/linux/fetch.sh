#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_linux
ARCH="$(arch)"

if [[ ! -x "$BIN_DIR/firecracker" ]]; then
  archive="$ASSET_DIR/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz"
  url="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz"
  echo "Downloading Firecracker ${FIRECRACKER_VERSION}..."
  curl --fail --location --retry 3 -o "$archive" "$url"
  unpack="$ASSET_DIR/firecracker-${FIRECRACKER_VERSION}-${ARCH}"
  rm -rf "$unpack"
  mkdir -p "$unpack"
  tar -xzf "$archive" -C "$unpack" --strip-components=1
  cp "$unpack/firecracker-${FIRECRACKER_VERSION}-${ARCH}" "$BIN_DIR/firecracker"
  chmod 0755 "$BIN_DIR/firecracker"
fi

if [[ ! -f "$ASSET_DIR/vmlinux" ]]; then
  s3="https://s3.amazonaws.com/spec.ccfc.min"
  echo "Downloading a Firecracker-compatible Linux kernel..."
  prefix="$(curl -fsSL "$s3?list-type=2&prefix=firecracker-ci/&delimiter=/" \
    | grep -oE '<Prefix>firecracker-ci/[0-9]{8}-[^<]+/</Prefix>' \
    | sed -E 's#</?Prefix>##g' | sort | tail -1)"
  [[ -n "$prefix" ]] || die "could not discover Firecracker CI artifacts"
  kernel_key="$(curl -fsSL "$s3?list-type=2&prefix=${prefix}${ARCH}/vmlinux-" \
    | grep -oE "<Key>${prefix}${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]+</Key>" \
    | sed -E 's#</?Key>##g' | sort -V | tail -1)"
  [[ -n "$kernel_key" ]] || die "could not discover a kernel for $ARCH"
  curl --fail --location --retry 3 -o "$ASSET_DIR/vmlinux" "$s3/$kernel_key"
  printf '%s\n' "$kernel_key" > "$ASSET_DIR/vmlinux.source"
fi

alpine_tar="alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
alpine_url="${ALPINE_MIRROR}/v${ALPINE_VERSION%.*}/releases/${ARCH}/${alpine_tar}"
if [[ ! -f "$ASSET_DIR/$alpine_tar" ]]; then
  echo "Downloading Alpine ${ALPINE_VERSION} minirootfs..."
  curl --fail --location --retry 3 -o "$ASSET_DIR/$alpine_tar" "$alpine_url"
  curl --fail --location --retry 3 -o "$ASSET_DIR/$alpine_tar.sha256" "$alpine_url.sha256"
  (cd "$ASSET_DIR" && sha256sum -c "$alpine_tar.sha256")
fi

echo "Assets are ready in $ASSET_DIR"
