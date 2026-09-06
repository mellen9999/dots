#!/bin/bash
# ananicy policy is NOT deployed by any sync job — run this after changing it.
set -euo pipefail
d="$(cd "$(dirname "$0")" && pwd)"
sudo install -Dm644 "$d/ananicy.conf"    /etc/ananicy.d/ananicy.conf
sudo install -Dm644 "$d/99-heatpc.rules" /etc/ananicy.d/99-heatpc.rules
sudo systemctl restart ananicy-cpp
echo "deployed; check: ps -eo ni,comm | sort -n | head"
