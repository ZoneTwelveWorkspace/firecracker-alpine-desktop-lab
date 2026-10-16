#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_linux
[[ -x "$BIN_DIR/firecracker" ]] || die "Firecracker is missing; run ./lab build"
for name in "${VM_NAMES[@]}"; do
  [[ -f "$IMAGE_DIR/$name.ext4" ]] || die "$name image is missing; run ./lab build"
done

sudo sysctl -q -w net.ipv4.ip_forward=1
host_iface="$(ip -json route show default | sed -n 's/.*"dev":"\([^"]*\)".*/\1/p' | head -1)"
[[ -n "$host_iface" ]] || die "could not discover the default network interface"

for i in 0 1; do
  name="${VM_NAMES[$i]}"
  tap="${TAP_NAMES[$i]}"
  run="$RUNTIME_DIR/$name"
  fc_unit="fc-$name"
  vnc_unit="fc-$name-vnc"
  ssh_unit="fc-$name-ssh"
  game_unit="fc-$name-game"
  mkdir -p "$run"

  if systemctl --user is-active --quiet "$fc_unit"; then
    echo "$name is already running"
    continue
  fi

  systemctl --user stop "$fc_unit" "$vnc_unit" "$ssh_unit" "$game_unit" 2>/dev/null || true
  systemctl --user reset-failed "$fc_unit" "$vnc_unit" "$ssh_unit" "$game_unit" 2>/dev/null || true

  sudo ip link del "$tap" 2>/dev/null || true
  sudo ip tuntap add dev "$tap" mode tap user "$(id -un)"
  sudo ip addr add "${HOST_IPS[$i]}/30" dev "$tap"
  sudo ip link set "$tap" up

  sudo iptables -t nat -C POSTROUTING -s "${VM_CIDRS[$i]}" -o "$host_iface" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -s "${VM_CIDRS[$i]}" -o "$host_iface" -j MASQUERADE
  sudo iptables -C FORWARD -i "$tap" -o "$host_iface" -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$tap" -o "$host_iface" -j ACCEPT
  sudo iptables -C FORWARD -i "$host_iface" -o "$tap" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$host_iface" -o "$tap" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  socket="$run/firecracker.sock"
  rm -f "$socket"
  cat > "$run/config.json" <<EOF
{
  "boot-source": {
    "kernel_image_path": "$ASSET_DIR/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw rootfstype=ext4 init=/sbin/init"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$IMAGE_DIR/$name.ext4",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "${VM_MACS[$i]}",
      "host_dev_name": "$tap"
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 2048,
    "smt": false
  }
}
EOF

  : > "$run/serial.log"
  : > "$run/vnc-proxy.log"
  : > "$run/ssh-proxy.log"
  : > "$run/game-proxy.log"
  systemd-run --user --quiet --unit "$fc_unit" --collect \
    --property=Type=exec \
    --property="StandardOutput=append:$run/serial.log" \
    --property="StandardError=append:$run/serial.log" \
    "$BIN_DIR/firecracker" --api-sock "$socket" --config-file "$run/config.json"

  systemd-run --user --quiet --unit "$vnc_unit" --collect \
    --property=Type=exec \
    --property="StandardOutput=append:$run/vnc-proxy.log" \
    --property="StandardError=append:$run/vnc-proxy.log" \
    socat "TCP-LISTEN:${VNC_PORTS[$i]},bind=0.0.0.0,reuseaddr,fork" \
    "TCP:${VM_IPS[$i]}:5900"
  systemd-run --user --quiet --unit "$ssh_unit" --collect \
    --property=Type=exec \
    --property="StandardOutput=append:$run/ssh-proxy.log" \
    --property="StandardError=append:$run/ssh-proxy.log" \
    socat "TCP-LISTEN:${SSH_PORTS[$i]},bind=0.0.0.0,reuseaddr,fork" \
    "TCP:${VM_IPS[$i]}:22"
  systemd-run --user --quiet --unit "$game_unit" --collect \
    --property=Type=exec \
    --property="StandardOutput=append:$run/game-proxy.log" \
    --property="StandardError=append:$run/game-proxy.log" \
    socat "TCP-LISTEN:${GAME_PORTS[$i]},bind=0.0.0.0,reuseaddr,fork" \
    "TCP:${VM_IPS[$i]}:8080"

  systemctl --user show "$fc_unit" --property=MainPID --value > "$run/firecracker.pid"
  systemctl --user show "$vnc_unit" --property=MainPID --value > "$run/vnc-proxy.pid"
  systemctl --user show "$ssh_unit" --property=MainPID --value > "$run/ssh-proxy.pid"
  systemctl --user show "$game_unit" --property=MainPID --value > "$run/game-proxy.pid"

  if novnc_available; then
    start_novnc_proxy "$i"
  fi

  echo "Started $name (VNC ${VNC_PORTS[$i]}, SSH ${SSH_PORTS[$i]}, game ${GAME_PORTS[$i]})."
done

echo "The desktops may need 20-40 seconds for Chromium to appear."
