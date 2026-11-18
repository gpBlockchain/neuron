#!/usr/bin/env bash
# Resolve CKB / light-client source settings for packaging.
# Prints KEY=VALUE lines suitable for GitHub Actions GITHUB_ENV.
# Does not print token values.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/ckb-clients.sh
. "$ROOT_DIR/scripts/lib/ckb-clients.sh"

# workflow_dispatch inputs are passed as INPUT_* and applied only when non-empty.
apply_input() {
  local envname="$1"
  local value="${2:-}"
  value="$(ckb_clients_trim "$value")"
  if [ -n "$value" ]; then
    export "$envname=$value"
  fi
}

apply_input CKB_SOURCE "${INPUT_CKB_SOURCE:-}"
apply_input CKB_REPO "${INPUT_CKB_REPO:-}"
apply_input CKB_REF "${INPUT_CKB_REF:-}"
apply_input CKB_URL "${INPUT_CKB_URL:-}"
apply_input CKB_ARTIFACT_RUN_ID "${INPUT_CKB_ARTIFACT_RUN_ID:-}"
apply_input CKB_ARTIFACT_NAME "${INPUT_CKB_ARTIFACT_NAME:-}"
apply_input CKB_ASSET_NAME "${INPUT_CKB_ASSET_NAME:-}"
apply_input CKB_LIGHT_SOURCE "${INPUT_LIGHT_CLIENT_SOURCE:-}"
apply_input CKB_LIGHT_REPO "${INPUT_LIGHT_CLIENT_REPO:-}"
apply_input CKB_LIGHT_REF "${INPUT_LIGHT_CLIENT_REF:-}"
apply_input CKB_LIGHT_URL "${INPUT_LIGHT_CLIENT_URL:-}"
apply_input CKB_LIGHT_ARTIFACT_RUN_ID "${INPUT_LIGHT_CLIENT_ARTIFACT_RUN_ID:-}"
apply_input CKB_LIGHT_ARTIFACT_NAME "${INPUT_LIGHT_CLIENT_ARTIFACT_NAME:-}"
apply_input CKB_LIGHT_ASSET_NAME "${INPUT_LIGHT_CLIENT_ASSET_NAME:-}"
apply_input UPLOAD_PACKAGES "${INPUT_UPLOAD_PACKAGES:-}"

if [ -n "${PACKAGE_COMMENT_BODY:-}" ]; then
  assignments="$(ckb_clients_parse_package_comment "$PACKAGE_COMMENT_BODY")"
  # Here-doc keeps apply_assignments in this shell so exports persist.
  ckb_clients_apply_assignments <<EOF
$assignments
EOF
fi

# GitHub URL inputs (releases/tag => release download, tree => source build)
# are applied after repo/ref/comment flags. Conflicts are rejected.
ckb_clients_apply_github_url CKB "${CKB_URL:-}" || exit 1
ckb_clients_apply_github_url CKB_LIGHT "${CKB_LIGHT_URL:-}" || exit 1

# If the user supplied a branch/tag/SHA and did not set a source mode, build
# from source. Leaving the ref empty keeps the official Release default.
# Explicit CKB_SOURCE / CKB_LIGHT_SOURCE (for example release or artifact) wins.
if [ -z "${CKB_SOURCE:-}" ] && [ -n "${CKB_REF:-}" ]; then
  CKB_SOURCE=source
  export CKB_SOURCE
fi
if [ -z "${CKB_LIGHT_SOURCE:-}" ] && [ -n "${CKB_LIGHT_REF:-}" ]; then
  CKB_LIGHT_SOURCE=source
  export CKB_LIGHT_SOURCE
fi

ckb_clients_load_defaults "$ROOT_DIR"
ckb_clients_validate_resolved
ckb_clients_export_upload_flags
ckb_clients_log_plan >&2

# Emit env for subsequent steps. Never emit token names' values.
cat <<EOF
CKB_SOURCE=${CKB_SOURCE}
CKB_REPO=${CKB_REPO}
CKB_REF=${CKB_REF}
CKB_ARTIFACT_RUN_ID=${CKB_ARTIFACT_RUN_ID:-}
CKB_ARTIFACT_NAME=${CKB_ARTIFACT_NAME:-}
CKB_ASSET_NAME=${CKB_ASSET_NAME:-}
CKB_LIGHT_SOURCE=${CKB_LIGHT_SOURCE}
CKB_LIGHT_REPO=${CKB_LIGHT_REPO}
CKB_LIGHT_REF=${CKB_LIGHT_REF}
CKB_LIGHT_ARTIFACT_RUN_ID=${CKB_LIGHT_ARTIFACT_RUN_ID:-}
CKB_LIGHT_ARTIFACT_NAME=${CKB_LIGHT_ARTIFACT_NAME:-}
CKB_LIGHT_ASSET_NAME=${CKB_LIGHT_ASSET_NAME:-}
UPLOAD_PACKAGES=${UPLOAD_PACKAGES:-true}
CKB_CLIENTS_SENSITIVE=${CKB_CLIENTS_SENSITIVE}
CKB_CLIENTS_SHOULD_UPLOAD=${CKB_CLIENTS_SHOULD_UPLOAD}
EOF
