#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/prod-config.sh"
prod_config "$REPO"
"${COMPOSE[@]}" up -d --no-deps backend
