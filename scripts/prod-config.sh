#!/usr/bin/env bash
# Sourced by production entrypoints. Never print credentials or rendered config.
prod_config() {
    local repo="$1"
    local env_file="${PROD_ENV_FILE:-$repo/deploy/.env}"
    [[ -f "$env_file" ]] || { echo 'Production env file is missing' >&2; return 1; }
    set -a
    source "$env_file"
    set +a
    PUBLIC_TUNNELS="${PUBLIC_TUNNELS:-ngrok}"
    PROD_TUNNEL_SERVICES=()
    PROD_PUBLIC_URLS=()
    case "$PUBLIC_TUNNELS" in
        ngrok|cloudflare|both) ;;
        *) echo 'PUBLIC_TUNNELS must be ngrok, cloudflare, or both' >&2; return 1 ;;
    esac
    if [[ "$PUBLIC_TUNNELS" != cloudflare ]]; then
        [[ -n "${NGROK_DOMAIN:-}" && -n "${NGROK_AUTHTOKEN:-}" ]] || {
            echo 'NGROK_DOMAIN and NGROK_AUTHTOKEN are required for ngrok' >&2; return 1;
        }
        PROD_TUNNEL_SERVICES+=(ngrok)
        PROD_PUBLIC_URLS+=("https://$NGROK_DOMAIN")
    fi
    if [[ "$PUBLIC_TUNNELS" != ngrok ]]; then
        [[ -n "${CLOUDFLARE_DOMAIN:-}" && -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]] || {
            echo 'CLOUDFLARE_DOMAIN and CLOUDFLARE_TUNNEL_TOKEN are required for Cloudflare' >&2; return 1;
        }
        PROD_TUNNEL_SERVICES+=(cloudflared)
        PROD_PUBLIC_URLS+=("https://$CLOUDFLARE_DOMAIN")
    fi
    local url found=false
    for url in "${PROD_PUBLIC_URLS[@]}"; do
        [[ "$url" =~ ^https://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || {
            echo 'Tunnel domains must be hostnames without scheme, path, or port' >&2; return 1;
        }
    done
    # Legacy env files keep their ngrok URL; dual mode requires an explicit choice.
    if [[ "$PUBLIC_TUNNELS" == both && -z "${PUBLIC_APP_URL:-}" ]]; then
        echo 'PUBLIC_APP_URL is required when both tunnels are enabled' >&2; return 1
    fi
    PUBLIC_APP_URL="${PUBLIC_APP_URL:-${PROD_PUBLIC_URLS[0]}}"
    for url in "${PROD_PUBLIC_URLS[@]}"; do
        [[ "$url" != "$PUBLIC_APP_URL" ]] || found=true
    done
    [[ "$found" == true ]] || {
        echo 'PUBLIC_APP_URL must match an enabled tunnel HTTPS origin' >&2; return 1;
    }
    PROD_CORS_ORIGINS=$(IFS=,; echo "${PROD_PUBLIC_URLS[*]}")
    export PUBLIC_APP_URL PROD_CORS_ORIGINS
    COMPOSE=(docker compose -f "$repo/deploy/docker-compose.yml" --env-file "$env_file")
    [[ "$PUBLIC_TUNNELS" == cloudflare ]] || COMPOSE+=(--profile ngrok)
    [[ "$PUBLIC_TUNNELS" == ngrok ]] || COMPOSE+=(--profile cloudflare)
    if [[ "${STT_DEVICE:-cpu}" == cuda || "${TTS_DEVICE:-cpu}" == cuda ]]; then
        COMPOSE+=(-f "$repo/deploy/docker-compose.gpu.yml")
    fi
}
