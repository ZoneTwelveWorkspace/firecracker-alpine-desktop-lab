#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

name="${1:-alpine-1}"
i="$(vm_index "$name")"
ip="${VM_IPS[$i]}"
tap="${TAP_NAMES[$i]}"
run="$RUNTIME_DIR/$name"
key="$PROJECT_ROOT/state/id_ed25519"

printf '\n[%s runtime]\n' "$name"
systemctl --user status "fc-$name" "fc-$name-vnc" "fc-$name-ssh" \
  "fc-$name-game" \
  --no-pager --lines=20 || true

printf '\n[%s network]\n' "$name"
ip -brief address show "$tap" || true
ip neigh show "$ip" || true
ping -c 2 -W 2 "$ip" || true

printf '\n[%s serial boot log]\n' "$name"
tail -n 160 "$run/serial.log" 2>/dev/null || true

printf '\n[%s proxy logs]\n' "$name"
tail -n 40 "$run/vnc-proxy.log" 2>/dev/null || true
tail -n 40 "$run/ssh-proxy.log" 2>/dev/null || true
tail -n 40 "$run/game-proxy.log" 2>/dev/null || true

if [[ ! -f "$key" ]]; then
  printf '\nGuest inspection skipped: missing %s\n' "$key"
  exit 0
fi

printf '\n[%s guest services]\n' "$name"
timeout 90 ssh \
  -o ConnectTimeout=60 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "$key" "root@$ip" \
  'ip address; ip route; rc-service local status 2>/dev/null || true; \
   netstat -lntp 2>/dev/null || true; \
   ls -l /etc/local.d/tictactoe.start /var/www/tictactoe/index.html 2>/dev/null || true; \
   pgrep -af "sway|wayvnc|chromium|Xvfb|tictactoe-http|nc -lk" || true; \
   tail -n 80 /var/log/tictactoe-httpd.log 2>/dev/null || true; \
   tail -n 120 /var/log/wayland.log 2>/dev/null || true; \
   tail -n 120 /var/log/wayvnc.log 2>/dev/null || true; \
   tail -n 80 /var/log/xvfb.log 2>/dev/null || true' \
  || printf 'Guest inspection timed out or failed.\n'
