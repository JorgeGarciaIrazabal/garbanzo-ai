#!/usr/bin/env bash
# Deploy the local main branch: Flutter web + backend image + prod compose
# stack (postgres / backend / ngrok) + Android APK.
#
# Builds from a pristine temporary git worktree of main, so it can run from
# any branch with a dirty tree. Safe to re-run; data lives in named volumes.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/deploy/.env"
COMPOSE=(docker compose -f "$REPO/deploy/docker-compose.yml" --env-file "$ENV_FILE")

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo ""; echo "==> $*"; }

# --- Preflight ---------------------------------------------------------------
[[ -f "$ENV_FILE" ]] || die "deploy/.env missing — cp deploy/.env.example deploy/.env and fill it in"
set -a; source "$ENV_FILE"; set +a
for var in NGROK_AUTHTOKEN NGROK_DOMAIN POSTGRES_PASSWORD SECRET_KEY GIT_SSH_KEY_PATH GIT_USER_NAME GIT_USER_EMAIL; do
    [[ -n "${!var:-}" ]] || die "$var is empty in deploy/.env"
done
[[ -f "$GIT_SSH_KEY_PATH" ]] || die "GIT_SSH_KEY_PATH ($GIT_SSH_KEY_PATH) does not exist"
[[ -f "$REPO/backend/firebase-service-account.json" ]] || die "backend/firebase-service-account.json missing (mounted into prod for push notifications)"
[[ -f "$REPO/android/app/google-services.json" ]] || die "android/app/google-services.json missing (required for the APK build)"
git -C "$REPO" rev-parse --verify --quiet main >/dev/null || die "no local main branch"
for pid in $(pgrep -x ngrok || true); do
    # Containerized ngrok (e.g. our own garbanzo-prod-ngrok-1, about to be
    # recreated by `compose up`) shows up in `pgrep` when the host doesn't
    # isolate PID namespaces. Only a process outside any docker cgroup is a
    # genuine competing host agent that would break the free-plan session limit.
    if ! grep -q docker "/proc/$pid/cgroup" 2>/dev/null; then
        die "a host ngrok agent (pid $pid) is running outside Docker and the free plan allows one session — stop it first: kill $pid"
    fi
done

SHA=$(git -C "$REPO" rev-parse --short main)
BUILD_NUMBER=$(git -C "$REPO" rev-list --count main)  # monotonic Android versionCode

# --- Pristine snapshot of main ------------------------------------------------
WT=$(mktemp -d "${TMPDIR:-/tmp}/garbanzo-deploy.XXXXXX")
cleanup() {
    git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf "$WT"
}
trap cleanup EXIT
step "Snapshotting main @ $SHA into a temp worktree"
git -C "$REPO" worktree add --detach "$WT" main >/dev/null
# Required for the Android build but gitignored:
cp "$REPO/android/app/google-services.json" "$WT/android/app/"

# --- Build --------------------------------------------------------------------
step "Building Flutter web"
(cd "$WT" && flutter build web --release --output backend/web)

step "Building backend image (garbanzo-backend:latest, :$SHA)"
docker build -t garbanzo-backend:latest -t "garbanzo-backend:$SHA" "$WT/backend"

# --- Ship ---------------------------------------------------------------------
step "Starting prod stack"
"${COMPOSE[@]}" up -d --remove-orphans

step "Waiting for backend health"
for i in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8001/api/v1/health >/dev/null 2>&1; then
        echo "backend healthy"
        break
    fi
    if [[ $i -eq 60 ]]; then
        "${COMPOSE[@]}" logs --tail=50 backend
        die "backend not healthy after 120s — logs above"
    fi
    sleep 2
done

step "Checking the public tunnel"
for i in $(seq 1 15); do
    if curl -fsS -H "ngrok-skip-browser-warning: 1" "https://$NGROK_DOMAIN/api/v1/health" >/dev/null 2>&1; then
        echo "https://$NGROK_DOMAIN is live"
        break
    fi
    if [[ $i -eq 15 ]]; then
        "${COMPOSE[@]}" logs --tail=30 ngrok
        die "tunnel not answering — logs above"
    fi
    sleep 2
done

# --- Android APK ----------------------------------------------------------------
step "Building Android APK (versionCode $BUILD_NUMBER)"
(cd "$WT" && flutter build apk --release \
    --dart-define=API_BASE_URL="https://$NGROK_DOMAIN" \
    --build-number="$BUILD_NUMBER")
mkdir -p "$REPO/dist"
cp "$WT/build/app/outputs/flutter-apk/app-release.apk" "$REPO/dist/garbanzo-ai-$SHA.apk"

echo ""
echo "Deployed main @ $SHA"
echo "  Web:    https://$NGROK_DOMAIN"
echo "  APK:    dist/garbanzo-ai-$SHA.apk   (adb install -r dist/garbanzo-ai-$SHA.apk)"
echo "  Image:  garbanzo-backend:$SHA"
echo "  Status: just deploy-status"
