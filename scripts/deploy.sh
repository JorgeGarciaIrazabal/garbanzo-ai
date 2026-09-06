#!/usr/bin/env bash
# Deploy the local main branch: Flutter web + backend image + prod compose
# stack (postgres / backend / ngrok) + Android APK. If an Android device is
# connected via adb, the APK is installed on it automatically.
#
# Builds from a pristine temporary git worktree of main, so it can run from
# any branch with a dirty tree. Safe to re-run; data lives in named volumes.
#
# After a successful deploy, generates an LLM-authored changelog section (via
# Codex, from this release's git log + user reports) into CHANGELOG.md, bumps
# the patch version in pubspec.yaml, commits both on main, creates an annotated
# tag v<version> (with the ngrok URL + changelog in the tag message so CI can
# extract them), and pushes both to origin. The signed APK is attached to the
# GitHub Release locally; CI adds the Linux + Windows desktop binaries.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/deploy/.env"
COMPOSE=(docker compose -f "$REPO/deploy/docker-compose.yml" --env-file "$ENV_FILE")

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo ""; echo "==> $*"; }

# --- Preflight ---------------------------------------------------------------
[[ -f "$ENV_FILE" ]] || die "deploy/.env missing — cp deploy/.env.example deploy/.env and fill it in"
set -a; source "$ENV_FILE"; set +a
STT_DEVICE="${STT_DEVICE:-cpu}"
TTS_DEVICE="${TTS_DEVICE:-cpu}"
GITHUB_REPO="${GITHUB_REPO:-JorgeGarciaIrazabal/garbanzo-ai}"
for device_var in STT_DEVICE TTS_DEVICE; do
    case "${!device_var}" in
        cpu|auto|cuda) ;;
        *) die "$device_var must be cpu, auto, or cuda" ;;
    esac
done
TORCH_VARIANT=cpu
if [[ "$STT_DEVICE" == cuda || "$TTS_DEVICE" == cuda ]]; then
    TORCH_VARIANT=cuda
    COMPOSE+=(-f "$REPO/deploy/docker-compose.gpu.yml")
fi
for var in NGROK_AUTHTOKEN NGROK_DOMAIN POSTGRES_PASSWORD SECRET_KEY GIT_SSH_KEY_PATH GIT_USER_NAME GIT_USER_EMAIL ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_ALIAS ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_PASSWORD; do
    [[ -n "${!var:-}" ]] || die "$var is empty in deploy/.env"
done
[[ -f "$GIT_SSH_KEY_PATH" ]] || die "GIT_SSH_KEY_PATH ($GIT_SSH_KEY_PATH) does not exist"
[[ -f "$ANDROID_KEYSTORE_PATH" ]] || die "ANDROID_KEYSTORE_PATH ($ANDROID_KEYSTORE_PATH) does not exist"
[[ -f "$REPO/backend/firebase-service-account.json" ]] || die "backend/firebase-service-account.json missing (mounted into prod for push notifications)"
[[ -f "$REPO/android/app/google-services.json" ]] || die "android/app/google-services.json missing (required for the APK build)"
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required to publish the APK release asset"
gh auth status --hostname github.com >/dev/null 2>&1 \
    || die "GitHub CLI is not authenticated — run 'gh auth login'"
git -C "$REPO" rev-parse --verify --quiet main >/dev/null || die "no local main branch"
[[ "$(git -C "$REPO" branch --show-current)" == main ]] || die "deploy from the main checkout"
[[ -z "$(git -C "$REPO" status --porcelain -- pubspec.yaml CHANGELOG.md)" ]] || die "release files contain local edits; preserve/commit them before deploying"
for pid in $(pgrep -x ngrok || true); do
    # Containerized ngrok (e.g. our own garbanzo-prod-ngrok-1, about to be
    # recreated by `compose up`) shows up in `pgrep` when the host doesn't
    # isolate PID namespaces. Only a process outside any docker cgroup is a
    # genuine competing host agent that would break the free-plan session limit.
    if ! grep -q docker "/proc/$pid/cgroup" 2>/dev/null; then
        die "a host ngrok agent (pid $pid) is running outside Docker and the free plan allows one session — stop it first: kill $pid"
    fi
done

mkdir -p "$REPO/.ai/local"
chmod 700 "$REPO/.ai/local"
exec 9>"$REPO/.ai/local/writer.lock"
flock -n 9 || die "integration/deployment writer is busy"
SOURCE_SHA=$(git -C "$REPO" rev-parse main)
SHA=$(git -C "$REPO" rev-parse --short main)
BUILD_NUMBER=$(git -C "$REPO" rev-list --count main)  # monotonic Android versionCode

# Current version from pubspec.yaml (e.g. "1.0.0+1" → "1.0.0")
CURRENT_VERSION=$(grep '^version:' "$REPO/pubspec.yaml" | sed 's/version: *//' | cut -d+ -f1)
[[ -n "$CURRENT_VERSION" ]] || die "could not parse version from pubspec.yaml"

bump_patch() {
    # Bump the last digit of a semver string (1.2.3 → 1.2.4)
    local v="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "$v"
    patch=$((patch + 1))
    echo "${major}.${minor}.${patch}"
}

# The version this deploy will be released as (tagged after a successful
# deploy, below). Baked into the backend image so /api/v1/health reports the
# same version the CI desktop builds of this release carry.
#
# If the computed tag already exists on the remote (e.g. a prior deploy
# shipped v1.0.10 but pubspec was later rolled back to 1.0.9), keep bumping
# the patch until we find a free tag. This prevents the "tag already exists"
# push rejection that would otherwise abort a deploy after everything has
# already shipped.
NEW_VERSION=$(bump_patch "$CURRENT_VERSION")
while git -C "$REPO" ls-remote --exit-code origin "refs/tags/v${NEW_VERSION}" >/dev/null 2>&1; do
    echo "WARNING: tag v${NEW_VERSION} already exists on origin — bumping to next patch"
    NEW_VERSION=$(bump_patch "$NEW_VERSION")
done

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

# --- Integrated quality gate --------------------------------------------------
step "Testing the exact source snapshot before shipping"
(cd "$WT" && just test)

# --- Build --------------------------------------------------------------------
step "Building Flutter web"
(cd "$WT" && flutter build web --release --wasm --output backend/web)

step "Building backend image (garbanzo-backend:latest, :$SHA)"
docker build --label "org.opencontainers.image.revision=$SOURCE_SHA" --build-arg "APP_VERSION=$NEW_VERSION" \
    --build-arg "TORCH_VARIANT=$TORCH_VARIANT" \
    -t garbanzo-backend:latest -t "garbanzo-backend:$SHA" "$WT/backend"

# Build every required release artifact before changing the running stack. A
# build failure therefore leaves the current production revision untouched.
step "Building Android APK (versionCode $BUILD_NUMBER)"
(cd "$WT" && flutter build apk --release \
    --dart-define=API_BASE_URL="https://$NGROK_DOMAIN" \
    --build-name="$NEW_VERSION" \
    --build-number="$BUILD_NUMBER")
mkdir -p "$REPO/dist"
APK_NAME="garbanzo-ai-android-${NEW_VERSION}.apk"
APK_PATH="$REPO/dist/$APK_NAME"
cp "$WT/build/app/outputs/flutter-apk/app-release.apk" "$APK_PATH"

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

# --- Install APK on a connected device (if any) -----------------------------
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
    step "Installing APK on connected Android device"
    adb install -r "$APK_PATH" && echo "APK installed on device." \
        || echo "WARNING: adb install failed — APK is still at $APK_PATH"
else
    echo ""
    echo "No Android device connected. To install the APK later:"
    echo "  just deploy-apk-install"
fi

echo ""
echo "Deployed main @ $SHA"
echo "  Web:    https://$NGROK_DOMAIN"
echo "  APK:    $APK_PATH"
echo "  Image:  garbanzo-backend:$SHA"
echo "  Status: just deploy-status"

# --- Changelog ----------------------------------------------------------------
# Generate a human-readable changelog section for this release and prepend it to
# CHANGELOG.md. The content is authored by an LLM (Codex) from the release's
# git log + the user reports it addressed; we only supply the raw inputs and the
# instructions (scripts/changelog-instructions.md). Best-effort: a changelog
# failure must never abort a deploy that has already shipped.
step "Generating changelog"
generate_changelog() {
    (cd "$REPO" && just ai-changelog "$NEW_VERSION" "$SOURCE_SHA")
}

fallback_changelog() {
    # Minimal deterministic changelog: raw feat/fix lines from the release range.
    # Insert the new section before the first existing "## v" (or at the end if
    # none yet), preserving the "# Changelog" header + blurb.
    local last_tag section tmp
    last_tag=$(git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || true)
    section="$WT/changelog-section.md"
    {
        echo "## v${NEW_VERSION} — $(date +%F)"
        echo ""
        git -C "$REPO" log --no-merges --format='%s' "${last_tag:+${last_tag}..}$SOURCE_SHA" \
            | grep -E '^(feat|fix)' | sed -E 's/^(feat|fix)(\([^)]*\))?: */- /' \
            || echo "- No user-facing changes."
        echo ""
    } > "$section"

    [[ -f "$REPO/CHANGELOG.md" ]] || printf '# Changelog\n\n' > "$REPO/CHANGELOG.md"
    tmp="$WT/changelog-new.md"
    if grep -q '^## v' "$REPO/CHANGELOG.md"; then
        # Splice the new section in just before the first release heading.
        awk -v sf="$section" '
            /^## v/ && !done { while ((getline l < sf) > 0) print l; done=1 }
            { print }
        ' "$REPO/CHANGELOG.md" > "$tmp"
    else
        cat "$REPO/CHANGELOG.md" "$section" > "$tmp"
    fi
    mv "$tmp" "$REPO/CHANGELOG.md"
}

if ! generate_changelog; then
    fallback_changelog
fi

# --- Tag & version bump -------------------------------------------------------
# Bump the patch version, commit on main (with the changelog), create an
# annotated tag, and push. The tag push triggers the GitHub Actions workflow
# that builds the desktop apps.
step "Bumping version and creating release tag"

# Update pubspec.yaml: keep the existing +build suffix (or add +1 if none)
BUILD_SUFFIX=$(grep '^version:' "$REPO/pubspec.yaml" | sed 's/version: *//' | cut -d+ -f2)
[[ -n "$BUILD_SUFFIX" ]] || BUILD_SUFFIX="1"
sed -i "s/^version:.*/version: ${NEW_VERSION}+${BUILD_SUFFIX}/" "$REPO/pubspec.yaml"

# Stage only these two paths so any stray edit Codex may have made to the
# working tree is not committed.
git -C "$REPO" add pubspec.yaml CHANGELOG.md
git -C "$REPO" commit --only pubspec.yaml CHANGELOG.md \
    -m "chore: bump version to ${NEW_VERSION}" >/dev/null

# Extract the top section of CHANGELOG.md (this release's notes) for the tag
# message: everything from the first "## v" up to the next "## v".
CHANGELOG_SECTION=$(awk '/^## v/{n++} n==1{print} n==2{exit}' "$REPO/CHANGELOG.md")

# Create an annotated tag. The tag message includes the ngrok URL on a line
# prefixed with "API_URL: " so the CI workflow can extract it, plus this
# release's changelog section.
git -C "$REPO" tag -a "v${NEW_VERSION}" \
    -m "Release v${NEW_VERSION}" \
    -m "API_URL: https://${NGROK_DOMAIN}" \
    -m "${CHANGELOG_SECTION}"

step "Pushing main + tag v${NEW_VERSION} to origin"
git -C "$REPO" push origin main
# Force the tag only locally-override case: we already verified the remote tag
# doesn't exist (see the ls-remote loop above), so a plain push is correct and
# a rejection here means the remote state changed mid-deploy — surface it
# clearly rather than masking a real conflict.
if ! git -C "$REPO" push origin "v${NEW_VERSION}" 2>&1; then
    echo ""
    echo "WARNING: Failed to push tag v${NEW_VERSION}. The deploy itself"
    echo "succeeded (web + backend + APK are live), but the GitHub Actions"
    echo "desktop-build workflow was NOT triggered. To finish the release:"
    echo "  1. Resolve the tag conflict on the remote."
    echo "  2. Run: git push origin v${NEW_VERSION}"
    echo "  CI: https://github.com/${GITHUB_REPO}/actions"
    exit 0
fi

# The local machine owns the Android artifact because its signing key never
# leaves the host. Create the release immediately with the APK; the desktop CI
# release job finds the same tag and appends its Linux/Windows assets later.
step "Publishing signed Android APK to GitHub Release"
if gh release view "v${NEW_VERSION}" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    if gh release view "v${NEW_VERSION}" --repo "$GITHUB_REPO" \
        --json assets --jq '.assets[].name' | grep -Fxq "$APK_NAME"; then
        echo "$APK_NAME is already attached to v${NEW_VERSION}."
    else
        gh release upload "v${NEW_VERSION}" "$APK_PATH#Android APK" \
            --repo "$GITHUB_REPO"
    fi
else
    gh release create "v${NEW_VERSION}" "$APK_PATH#Android APK" \
        --repo "$GITHUB_REPO" \
        --verify-tag \
        --title "Release v${NEW_VERSION}" \
        --notes "$CHANGELOG_SECTION"
fi

echo ""
echo "Release tag v${NEW_VERSION} pushed."
echo "  Android APK: attached to the GitHub Release."
echo "  Desktop builds: GitHub Actions will append Linux + Windows binaries."
echo "  CI:     https://github.com/${GITHUB_REPO}/actions"
echo "  Release: https://github.com/${GITHUB_REPO}/releases/tag/v${NEW_VERSION}"

# Record build source separately from the later version-bump release commit.
(cd "$REPO" && just ai-deployment-evidence "$NEW_VERSION" "$SOURCE_SHA" "$(git rev-parse main)")
