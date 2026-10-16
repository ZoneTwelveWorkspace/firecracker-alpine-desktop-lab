#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

host_iface="$(ip -json route show default 2>/dev/null | sed -n 's/.*"dev":"\([^"]*\)".*/\1/p' | head -1)"

for i in 0 1; do
  name="${VM_NAMES[$i]}"
  run="$RUNTIME_DIR/$name"
  systemctl --user stop "fc-$name" "fc-$name-vnc" "fc-$name-ssh" \
    "fc-$name-game" "fc-$name-novnc" 2>/dev/null || true
  systemctl --user reset-failed "fc-$name" "fc-$name-vnc" "fc-$name-ssh" \
    "fc-$name-game" "fc-$name-novnc" 2>/dev/null || true
  for pid_name in firecracker vnc-proxy ssh-proxy game-proxy novnc; do
    pid_file="$run/$pid_name.pid"
    if pid_alive "$pid_file"; then
      kill "$(cat "$pid_file")" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  done
  sudo ip link del "${TAP_NAMES[$i]}" 2>/dev/null || true
  if [[ -n "$host_iface" ]]; then
    sudo iptables -t nat -D POSTROUTING -s "${VM_CIDRS[$i]}" -o "$host_iface" -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i "${TAP_NAMES[$i]}" -o "$host_iface" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -i "$host_iface" -o "${TAP_NAMES[$i]}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  fi
  rm -f "$run/firecracker.sock"
  echo "Stopped $name."
done
