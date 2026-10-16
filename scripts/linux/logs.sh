#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

name="${1:-alpine-1}"
vm_index "$name" >/dev/null
log="$RUNTIME_DIR/$name/serial.log"
[[ -f "$log" ]] || die "no log for $name; start it first"
exec tail -n 120 -f "$log"
