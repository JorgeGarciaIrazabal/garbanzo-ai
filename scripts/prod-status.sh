#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/prod-config.sh"
prod_config "$REPO"
"${COMPOSE[@]}" ps
failed=0
for url in http://127.0.0.1:8001 "${PROD_PUBLIC_URLS[@]}"; do
    if curl --connect-timeout 5 --max-time 15 -fsS -H 'ngrok-skip-browser-warning: 1' "$url/api/v1/health" >/dev/null; then
        echo "$url — OK"
    else
        echo "$url — DOWN"
        failed=1
    fi
done
exit "$failed"
