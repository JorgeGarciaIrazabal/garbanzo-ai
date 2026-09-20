#!/usr/bin/env bash
# Explicitly retire a connector after removing it from PUBLIC_TUNNELS.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/prod-config.sh"
prod_config "$REPO"
service="${1:?Specify ngrok or cloudflared}"
case "$service" in
    ngrok|cloudflared) ;;
    *) echo 'Specify ngrok or cloudflared' >&2; exit 1 ;;
esac
"${COMPOSE[@]}" stop "$service"
