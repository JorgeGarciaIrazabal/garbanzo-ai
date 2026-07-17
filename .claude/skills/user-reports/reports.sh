#!/usr/bin/env bash
# Read and triage user-submitted bug reports / feature requests from the
# production database (`reports` table, migration 026).
#
# Usage:
#   reports.sh list [--type bug|feature] [--status open|in_progress|closed|all]
#   reports.sh show <report-id>
#   reports.sh set-status <report-id> open|in_progress|closed
#
# All access goes through the prod compose stack's psql escape hatch
# (deploy/README.md). The DB is read-only except for `set-status`, which only
# ever updates a single row by id.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPOSE=(docker compose -f "$REPO_ROOT/deploy/docker-compose.yml" --env-file "$REPO_ROOT/deploy/.env")
PSQL=("${COMPOSE[@]}" exec -T postgres psql -U garbanzo -d garbanzo_ai_prod)

die() { echo "error: $*" >&2; exit 1; }

require_postgres() {
  "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx postgres \
    || die "prod postgres is not running — check 'just deploy-status' (WSL2: sudo service docker start)"
}

# Report ids are uuid strings; strict validation keeps the SQL injection-safe.
valid_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

build_where() {
  local where_sql=""
  local cond
  for cond in "$@"; do
    if [[ -z "$where_sql" ]]; then
      where_sql="WHERE $cond"
    else
      where_sql="$where_sql AND $cond"
    fi
  done
  echo "$where_sql"
}

cmd_list() {
  local type="" status=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)   type="${2:?--type needs a value: bug|feature}"; shift 2 ;;
      --status) status="${2:?--status needs a value: open|in_progress|closed|all}"; shift 2 ;;
      *) die "unknown list option: $1" ;;
    esac
  done

  local conds=()
  if [[ -n "$type" ]]; then
    [[ "$type" == bug || "$type" == feature ]] || die "--type must be bug or feature"
    conds+=("type = '$type'")
  fi
  case "$status" in
    "") conds+=("status != 'closed'") ;;            # default: everything still open
    all) ;;                                          # no status filter
    open|in_progress|closed) conds+=("status = '$status'") ;;
    *) die "--status must be open, in_progress, closed or all" ;;
  esac

  require_postgres
  "${PSQL[@]}" -c "SELECT id, type, status, title, user_id, created_at
                   FROM reports $(build_where "${conds[@]}")
                   ORDER BY (type = 'bug') DESC, created_at DESC;"
}

cmd_show() {
  local id="${1:?usage: reports.sh show <report-id>}"
  valid_uuid "$id" || die "invalid report id: $id"
  require_postgres
  # -x: expanded output so long descriptions stay readable.
  "${PSQL[@]}" -x -c "SELECT id, type, status, title, description, user_id, created_at, updated_at
                      FROM reports WHERE id = '$id';"
}

cmd_set_status() {
  local id="${1:?usage: reports.sh set-status <report-id> open|in_progress|closed}"
  local status="${2:?usage: reports.sh set-status <report-id> open|in_progress|closed}"
  valid_uuid "$id" || die "invalid report id: $id"
  [[ "$status" == open || "$status" == in_progress || "$status" == closed ]] \
    || die "status must be open, in_progress or closed"

  require_postgres
  # updated_at only auto-bumps through the ORM — raw SQL must set it explicitly.
  "${PSQL[@]}" -c "UPDATE reports SET status = '$status', updated_at = NOW()
                   WHERE id = '$id';"
}

usage() {
  cat <<'EOF'
Usage:
  reports.sh list [--type bug|feature] [--status open|in_progress|closed|all]
                  List reports (default: all non-closed, bugs first, newest first)
  reports.sh show <report-id>
                  Print one report in full, including the description
  reports.sh set-status <report-id> open|in_progress|closed
                  Triage a report (single-row UPDATE by id)
EOF
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then usage; exit 1; fi
shift
case "$cmd" in
  list)       cmd_list "$@" ;;
  show)       cmd_show "$@" ;;
  set-status) cmd_set_status "$@" ;;
  -h|--help)  usage ;;
  *)          die "unknown command: $cmd (see --help)" ;;
esac
