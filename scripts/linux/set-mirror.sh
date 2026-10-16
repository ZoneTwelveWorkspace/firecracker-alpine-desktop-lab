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

branch="v${ALPINE_VERSION%.*}"
for ip in "${VM_IPS[@]}"; do
  echo "Setting Alpine mirror on $ip to $ALPINE_MIRROR..."
  printf '%s\n' \
    "$ALPINE_MIRROR/$branch/main" \
    "$ALPINE_MIRROR/$branch/community" \
    | ssh "${ssh_options[@]}" "root@$ip" \
      'cat > /etc/apk/repositories && timeout 90 apk update'
done

echo "Both guests now use $ALPINE_MIRROR."
