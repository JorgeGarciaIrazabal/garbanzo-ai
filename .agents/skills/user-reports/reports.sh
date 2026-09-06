#!/usr/bin/env bash
# Read and triage user-submitted bug reports / feature requests from the
# production database (`reports` table, migration 026).
#
# Usage:
#   reports.sh list [--type bug|feature] [--status open|in_progress|closed|all]
#                   [--limit N] [--after-updated ISO] [--after-id UUID] [--json]
#   reports.sh show <report-id>
#   reports.sh set-status <report-id> open|in_progress|closed
#
# All access goes through the prod compose stack's psql escape hatch
# (deploy/README.md). The DB is read-only except for `set-status`, which only
# ever updates a single row by id.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
die() { echo "error: $*" >&2; exit 1; }

require_postgres() {
  local services
  services="$(just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" ai-prod-services 2>/dev/null)" \
    || die "cannot inspect prod postgres — check 'just deploy-status' (WSL2: sudo service docker start)"
  grep -q '"Service":"postgres"' <<<"$services" \
    || die "prod postgres is not running — check 'just deploy-status' (WSL2: sudo service docker start)"
}

run_sql() {
  just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" ai-prod-sql <<<"$1"
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
  local type="" status="" after_updated="" after_id="" json=false limit=50
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)   type="${2:?--type needs a value: bug|feature}"; shift 2 ;;
      --status) status="${2:?--status needs a value: open|in_progress|closed|all}"; shift 2 ;;
      --limit) limit="${2:?--limit needs a value}"; shift 2 ;;
      --after-updated) after_updated="${2:?--after-updated needs a value}"; shift 2 ;;
      --after-id) after_id="${2:?--after-id needs a value}"; shift 2 ;;
      --json) json=true; shift ;;
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
  [[ "$limit" =~ ^[1-9][0-9]*$ ]] && (( limit <= 500 )) || die "--limit must be 1..500"
  if [[ -n "$after_updated" || -n "$after_id" ]]; then
    [[ -n "$after_updated" && -n "$after_id" ]] || die "cursor requires both --after-updated and --after-id"
    valid_uuid "$after_id" || die "invalid cursor report id: $after_id"
    [[ "$after_updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[T\ ][0-9:.+-]+$ ]] || die "invalid cursor timestamp"
    conds+=("(updated_at, id) > ('$after_updated'::timestamptz, '$after_id')")
  fi

  require_postgres
  local select_sql="SELECT id, type, status, title, description, user_id,
                           metadata, conversation_id, severity, source,
                           created_at, updated_at, xmin::text AS version
                    FROM reports $(build_where "${conds[@]}")
                    ORDER BY updated_at, id LIMIT $limit"
  if [[ "$json" == true ]]; then
    run_sql "SELECT COALESCE(json_agg(row_to_json(page)), '[]'::json) FROM ($select_sql) page;"
  else
    run_sql "$select_sql;"
  fi
}

cmd_show() {
  local id="${1:?usage: reports.sh show <report-id>}"
  valid_uuid "$id" || die "invalid report id: $id"
  require_postgres
  # -x: expanded output so long descriptions stay readable.
  run_sql "SELECT id, type, status, title, description, user_id, metadata,
                  conversation_id, severity, source, created_at, updated_at,
                  xmin::text AS version FROM reports WHERE id = '$id';"
}

cmd_set_status() {
  local id="${1:?usage: reports.sh set-status <report-id> open|in_progress|closed}"
  local status="${2:?usage: reports.sh set-status <report-id> open|in_progress|closed}"
  local expected_status="${3:?usage: reports.sh set-status <report-id> <new-status> <expected-status> <expected-updated-at>}"
  local expected_updated="${4:?usage: reports.sh set-status <report-id> <new-status> <expected-status> <expected-updated-at>}"
  local expected_version="${5:?usage: reports.sh set-status <report-id> <new-status> <expected-status> <expected-updated-at> <expected-version>}"
  valid_uuid "$id" || die "invalid report id: $id"
  [[ "$status" == open || "$status" == in_progress || "$status" == closed ]] \
    || die "status must be open, in_progress or closed"
  [[ "$expected_status" == open || "$expected_status" == in_progress || "$expected_status" == closed ]] \
    || die "expected status must be open, in_progress or closed"
  case "$expected_status:$status" in
    open:in_progress|in_progress:open|in_progress:closed|closed:in_progress) ;;
    *) die "invalid status transition: $expected_status -> $status" ;;
  esac
  [[ "$expected_updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[T\ ][0-9:.+-]+$ ]] || die "invalid expected updated_at"
  [[ "$expected_version" =~ ^[0-9]+$ ]] || die "invalid expected row version"

  require_postgres
  # updated_at only auto-bumps through the ORM — raw SQL must set it explicitly.
  local result
  result="$(run_sql "UPDATE reports SET status = '$status', updated_at = NOW()
                    WHERE id = '$id' AND status = '$expected_status'
                      AND updated_at = '$expected_updated'::timestamptz
                      AND xmin = '$expected_version'::xid
                    RETURNING row_to_json(reports);")"
  [[ -n "$result" ]] || die "report changed concurrently or does not exist"
  printf '%s\n' "$result"
}

usage() {
  cat <<'EOF'
Usage:
  reports.sh list [--type bug|feature] [--status open|in_progress|closed|all]
                  List reports (default: all non-closed, bugs first, newest first)
  reports.sh show <report-id>
                  Print one report in full, including the description
  reports.sh set-status <report-id> <new-status> <expected-status> <expected-updated-at> <expected-version>
                  Compare-and-set one report using a valid lifecycle transition
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
