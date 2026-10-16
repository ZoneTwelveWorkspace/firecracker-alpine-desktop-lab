#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_linux
key="$PROJECT_ROOT/state/id_ed25519"
[[ -f "$key" ]] || die "missing SSH key; run ./lab build first"

ssh_options=(
  -o ConnectTimeout=60
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -i "$key"
)

for ip in "${VM_IPS[@]}"; do
  echo "Updating desktop services on $ip..."
  scp "${ssh_options[@]}" -r \
    "$PROJECT_ROOT/config/sway.conf" \
    "$PROJECT_ROOT/config/wayland.start" \
    "$PROJECT_ROOT/config/xvfb.start" \
    "$PROJECT_ROOT/config/tictactoe-http" \
    "$PROJECT_ROOT/config/tictactoe.start" \
    "$PROJECT_ROOT/config/tictactoe" \
    "root@$ip:/tmp/"
  ssh "${ssh_options[@]}" "root@$ip" \
    "if ! command -v Xvfb >/dev/null; then apk add --no-cache xvfb; fi && \
     install -d -m 0755 /var/www/tictactoe && \
     cp -a /tmp/tictactoe/. /var/www/tictactoe/ && \
     install -m 0644 /tmp/sway.conf /etc/sway/config && \
     install -m 0755 /tmp/tictactoe-http /usr/local/bin/tictactoe-http && \
     install -m 0755 /tmp/wayland.start /etc/local.d/wayland.start && \
     install -m 0755 /tmp/xvfb.start /etc/local.d/xvfb.start && \
     install -m 0755 /tmp/tictactoe.start /etc/local.d/tictactoe.start && \
     sync"
done

bash "$PROJECT_ROOT/scripts/linux/down.sh"
bash "$PROJECT_ROOT/scripts/linux/up.sh"

echo "Desktop services and Tic-Tac-Toe updated; allow up to 2 minutes for Chromium startup."
