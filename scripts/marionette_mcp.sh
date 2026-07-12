#!/usr/bin/env bash
# MCP launcher for marionette_mcp (see .mcp.json).
#
# marionette_mcp (the MCP server) and marionette_flutter (the in-app binding,
# resolved from pubspec.lock) must be the exact same version or `connect`
# fails with a version-mismatch error. The two are installed independently —
# one via `dart pub global`, the other via `flutter pub get` — so they drift.
# This launcher re-syncs the global server to whatever version the app
# resolved, every time the MCP server is spawned.
#
# Everything before the final exec writes to stderr only: stdout is the MCP
# stdio channel and must carry nothing but protocol messages.
set -euo pipefail
cd "$(dirname "$0")/.."

want=$(sed -n '/^  marionette_flutter:$/,/version:/ s/^ *version: "\(.*\)"$/\1/p' pubspec.lock | head -1)
have=$(dart pub global list 2>/dev/null | sed -n 's/^marionette_mcp \([^ ]*\).*/\1/p')

if [ -n "$want" ] && [ "$want" != "$have" ]; then
  echo "marionette_mcp $have != marionette_flutter $want — activating $want" >&2
  dart pub global activate marionette_mcp "$want" >&2
fi

exec marionette_mcp
