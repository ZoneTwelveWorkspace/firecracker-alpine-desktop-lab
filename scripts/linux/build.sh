#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_linux
bash "$PROJECT_ROOT/scripts/linux/fetch.sh"

[[ -f "$PROJECT_ROOT/state/id_ed25519.pub" ]] \
  || die "missing host SSH key; run the build through ./lab"

if ((EUID != 0)); then
  exec sudo -E PROJECT_ROOT="$PROJECT_ROOT" FIRECRACKER_LAB_DATA="$DATA_DIR" \
    FIRECRACKER_VERSION="$FIRECRACKER_VERSION" ALPINE_VERSION="$ALPINE_VERSION" \
    ALPINE_MIRROR="$ALPINE_MIRROR" \
    bash "$0"
fi

ARCH="$(arch)"
alpine_tar="$ASSET_DIR/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
work="$(mktemp -d "$DATA_DIR/rootfs-build.XXXXXX")"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

echo "Creating Alpine base filesystem..."
mkdir -p "$work/base"
tar -xzf "$alpine_tar" -C "$work/base"
cp /etc/resolv.conf "$work/base/etc/resolv.conf"
printf '%s\n' \
  "${ALPINE_MIRROR}/v${ALPINE_VERSION%.*}/main" \
  "${ALPINE_MIRROR}/v${ALPINE_VERSION%.*}/community" \
  > "$work/base/etc/apk/repositories"

chroot "$work/base" /sbin/apk update
chroot "$work/base" /sbin/apk add \
  alpine-base openrc openssh ca-certificates curl \
  sway swaybg swaybar swaynag waybar wayvnc foot chromium \
  dbus dbus-openrc seatd mesa-dri-gallium mesa-egl mesa-gles \
  font-dejavu ttf-liberation xvfb

chroot "$work/base" /bin/sh -c 'passwd -d root'
chroot "$work/base" /sbin/rc-update add devfs sysinit || true
chroot "$work/base" /sbin/rc-update add procfs sysinit || true
chroot "$work/base" /sbin/rc-update add sysfs sysinit || true
chroot "$work/base" /sbin/rc-update add networking boot
chroot "$work/base" /sbin/rc-update add dbus default
chroot "$work/base" /sbin/rc-update add sshd default

mkdir -p "$work/base/root/.ssh" "$work/base/etc/sway" "$work/base/etc/local.d" \
  "$work/base/var/www/tictactoe" "$work/base/usr/local/bin"
install -m 0600 "$PROJECT_ROOT/state/id_ed25519.pub" "$work/base/root/.ssh/authorized_keys"
install -m 0644 "$PROJECT_ROOT/config/sway.conf" "$work/base/etc/sway/config"
cp -a "$PROJECT_ROOT/config/tictactoe/." "$work/base/var/www/tictactoe/"
install -m 0755 "$PROJECT_ROOT/config/tictactoe-http" \
  "$work/base/usr/local/bin/tictactoe-http"
chmod 0700 "$work/base/root/.ssh"

cat >> "$work/base/etc/ssh/sshd_config" <<'EOF'

PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

install -m 0755 "$PROJECT_ROOT/config/wayland.start" \
  "$work/base/etc/local.d/wayland.start"
install -m 0755 "$PROJECT_ROOT/config/xvfb.start" \
  "$work/base/etc/local.d/xvfb.start"
install -m 0755 "$PROJECT_ROOT/config/tictactoe.start" \
  "$work/base/etc/local.d/tictactoe.start"
chroot "$work/base" /sbin/rc-update add local default

cat > "$work/base/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
::shutdown:/sbin/openrc shutdown
EOF

cat > "$work/base/etc/motd" <<'EOF'
Firecracker Alpine Wayland Lab
Sway + Chromium are available through the VM's VNC desktop.
Chromium opens the guest-local Tic-Tac-Toe app automatically.
EOF

for i in 0 1; do
  name="${VM_NAMES[$i]}"
  guest="$work/$name"
  cp -a "$work/base" "$guest"
  printf '%s\n' "$name" > "$guest/etc/hostname"
  cat > "$guest/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address ${VM_IPS[$i]}
    netmask 255.255.255.252
    gateway ${HOST_IPS[$i]}
EOF
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$guest/etc/resolv.conf"
  rm -f "$guest/etc/ssh/ssh_host_"*
  chroot "$guest" /usr/bin/ssh-keygen -A

  image="$IMAGE_DIR/$name.ext4"
  echo "Packing $name GUI rootfs..."
  rm -f "$image"
  truncate -s 3G "$image"
  mkfs.ext4 -q -F -d "$guest" -L "$name" "$image"
  chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$image"
done

chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$DATA_DIR"
echo "Built ${VM_NAMES[*]} with Sway, Chromium, Tic-Tac-Toe, VNC, and SSH."
