#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_linux

if ! novnc_available; then
  echo "Installing noVNC and Websockify in the outer Linux host..."
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y novnc websockify
fi

novnc_available || die "noVNC installation did not provide $NOVNC_WEB_ROOT/vnc.html"

for i in 0 1; do
  systemctl --user is-active --quiet "fc-${VM_NAMES[$i]}" \
    || die "${VM_NAMES[$i]} is not running; run ./lab up first"
  start_novnc_proxy "$i"
  echo "Started ${VM_NAMES[$i]} browser viewer on port ${NOVNC_PORTS[$i]}."
done
