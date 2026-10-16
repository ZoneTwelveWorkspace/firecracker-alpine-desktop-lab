#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_linux

packages=(curl ca-certificates iproute2 iptables e2fsprogs openssh-client socat tar gzip xz-utils)
missing=()
for command_name in curl ip iptables mkfs.ext4 ssh-keygen socat tar; do
  command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done

if ((${#missing[@]})); then
  command -v apt-get >/dev/null 2>&1 || die "missing tools: ${missing[*]}"
  echo "Installing Linux host prerequisites..."
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
fi

if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  sudo setfacl -m "u:$(id -un):rw" /dev/kvm 2>/dev/null || sudo chmod 0666 /dev/kvm
fi

echo "Linux KVM host is ready ($(arch), Firecracker $FIRECRACKER_VERSION)."
