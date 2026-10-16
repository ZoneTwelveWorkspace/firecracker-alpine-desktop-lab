#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

printf '%-12s %-10s %-20s %-20s %-24s %-20s\n' NAME STATE VNC SSH WEB GAME
for i in 0 1; do
  name="${VM_NAMES[$i]}"
  run="$RUNTIME_DIR/$name"
  state=stopped
  systemctl --user is-active --quiet "fc-$name" && state=running
  web=stopped
  systemctl --user is-active --quiet "fc-$name-novnc" \
    && web="127.0.0.1:${NOVNC_PORTS[$i]}"
  game=stopped
  systemctl --user is-active --quiet "fc-$name-game" \
    && game="127.0.0.1:${GAME_PORTS[$i]}"
  printf '%-12s %-10s %-20s %-20s %-24s %-20s\n' \
    "$name" "$state" "127.0.0.1:${VNC_PORTS[$i]}" \
    "127.0.0.1:${SSH_PORTS[$i]}" "$web" "$game"
done
