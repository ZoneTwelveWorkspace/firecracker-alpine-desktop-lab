#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_DIR="${FIRECRACKER_LAB_DATA:-$HOME/.local/share/firecracker-alpine-lab}"
ASSET_DIR="$DATA_DIR/assets"
IMAGE_DIR="$DATA_DIR/images"
RUNTIME_DIR="$DATA_DIR/runtime"
BIN_DIR="$DATA_DIR/bin"

FIRECRACKER_VERSION="${FIRECRACKER_VERSION:-v1.17.0}"
ALPINE_VERSION="${ALPINE_VERSION:-3.24.2}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://alpine.cs.nycu.edu.tw}"
ALPINE_MIRROR="${ALPINE_MIRROR%/}"

VM_NAMES=(alpine-1 alpine-2)
VM_IPS=(172.30.1.2 172.30.2.2)
HOST_IPS=(172.30.1.1 172.30.2.1)
VM_CIDRS=(172.30.1.0/30 172.30.2.0/30)
TAP_NAMES=(fc-tap1 fc-tap2)
VM_MACS=(06:FC:00:00:01:02 06:FC:00:00:02:02)
VNC_PORTS=(5901 5902)
SSH_PORTS=(2221 2222)
NOVNC_PORTS=(6081 6082)
GAME_PORTS=(8081 8082)
NOVNC_WEB_ROOT="${NOVNC_WEB_ROOT:-/usr/share/novnc}"

mkdir -p "$ASSET_DIR" "$IMAGE_DIR" "$RUNTIME_DIR" "$BIN_DIR"

die() {
  echo "error: $*" >&2
  exit 1
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "Firecracker requires a Linux KVM host"
  [[ -e /dev/kvm ]] || die "/dev/kvm is missing; nested virtualization is not available"
}

arch() {
  case "$(uname -m)" in
    aarch64|arm64) echo aarch64 ;;
    x86_64) echo x86_64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

vm_index() {
  case "$1" in
    alpine-1) echo 0 ;;
    alpine-2) echo 1 ;;
    *) die "unknown VM '$1' (expected alpine-1 or alpine-2)" ;;
  esac
}

pid_alive() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  kill -0 "$(cat "$pid_file")" 2>/dev/null
}

novnc_available() {
  command -v websockify >/dev/null 2>&1 \
    && [[ -f "$NOVNC_WEB_ROOT/vnc.html" ]]
}

start_novnc_proxy() {
  local i="$1"
  local name="${VM_NAMES[$i]}"
  local run="$RUNTIME_DIR/$name"
  local unit="fc-$name-novnc"

  mkdir -p "$run"
  systemctl --user stop "$unit" 2>/dev/null || true
  systemctl --user reset-failed "$unit" 2>/dev/null || true
  : > "$run/novnc.log"
  systemd-run --user --quiet --unit "$unit" --collect \
    --property=Type=exec \
    --property="StandardOutput=append:$run/novnc.log" \
    --property="StandardError=append:$run/novnc.log" \
    websockify --web="$NOVNC_WEB_ROOT" \
    "0.0.0.0:${NOVNC_PORTS[$i]}" "${VM_IPS[$i]}:5900"
  systemctl --user show "$unit" --property=MainPID --value \
    > "$run/novnc.pid"
}
