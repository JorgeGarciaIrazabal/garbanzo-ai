#!/usr/bin/env bash
# Add/update a connector without restarting the backend or removing old services.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/prod-config.sh"
prod_config "$REPO"
service="${1:?Specify cloudflared or ngrok}"
for enabled in "${PROD_TUNNEL_SERVICES[@]}"; do
    if [[ "$enabled" == "$service" ]]; then
        exec "${COMPOSE[@]}" up -d --no-deps "$service"
    fi
done
echo 'Requested connector is not enabled in PUBLIC_TUNNELS' >&2
exit 1
