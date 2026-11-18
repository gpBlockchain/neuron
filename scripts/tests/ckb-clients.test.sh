#!/usr/bin/env bash
# Isolated regression tests for CKB / light-client source resolution.
# These tests do not require private tokens and do not package Neuron.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/ckb-clients.sh
. "$ROOT_DIR/scripts/lib/ckb-clients.sh"

FAILS=0
PASS=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "ok - $label"
  else
    FAILS=$((FAILS + 1))
    echo "not ok - $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

assert_ok() {
  local label="$1"
  if shift; "$@"; then
    PASS=$((PASS + 1))
    echo "ok - $label"
  else
    FAILS=$((FAILS + 1))
    echo "not ok - $label (command failed)"
  fi
}

assert_fail() {
  local label="$1"
  if shift; "$@"; then
    FAILS=$((FAILS + 1))
    echo "not ok - $label (expected failure)"
  else
    PASS=$((PASS + 1))
    echo "ok - $label"
  fi
}

# --- official names and default URL construction ---
assert_eq "linux ckb asset name" \
  "ckb_v0.209.0_x86_64-unknown-linux-gnu-portable.tar.gz" \
  "$(ckb_clients_ckb_asset_name linux "" v0.209.0)"

assert_eq "windows ckb asset name" \
  "ckb_v0.209.0_x86_64-pc-windows-msvc.zip" \
  "$(ckb_clients_ckb_asset_name win "" v0.209.0)"

assert_eq "mac x64 ckb asset name" \
  "ckb_v0.209.0_x86_64-apple-darwin-portable.zip" \
  "$(ckb_clients_ckb_asset_name mac x86_64 v0.209.0)"

assert_eq "mac arm64 ckb asset name" \
  "ckb_v0.209.0_aarch64-apple-darwin-portable.zip" \
  "$(ckb_clients_ckb_asset_name mac arm64 v0.209.0)"

assert_eq "linux light asset name" \
  "ckb-light-client_v0.5.4-x86_64-linux-portable.tar.gz" \
  "$(ckb_clients_light_asset_name linux v0.5.4)"

assert_eq "mac light asset name" \
  "ckb-light-client_v0.5.4-x86_64-darwin-portable.tar.gz" \
  "$(ckb_clients_light_asset_name mac v0.5.4)"

assert_eq "win light asset name" \
  "ckb-light-client_v0.5.4-x86_64-windows.tar.gz" \
  "$(ckb_clients_light_asset_name win v0.5.4)"

assert_eq "official public release URL" \
  "https://github.com/nervosnetwork/ckb-light-client/releases/download/v0.5.4/ckb-light-client_v0.5.4-x86_64-linux-portable.tar.gz" \
  "$(ckb_clients_github_release_url nervosnetwork/ckb-light-client v0.5.4 ckb-light-client_v0.5.4-x86_64-linux-portable.tar.gz)"

# develop is a branch, not a release tag; the constructed URL is still a tag-style download.
assert_eq "develop is treated as a release tag in release mode (not a special branch URL)" \
  "https://github.com/nervosnetwork/ckb-light-client/releases/download/develop/ckb-light-client_develop-x86_64-linux-portable.tar.gz" \
  "$(ckb_clients_github_release_url nervosnetwork/ckb-light-client develop ckb-light-client_develop-x86_64-linux-portable.tar.gz)"

assert_eq "private release download uses API asset URL, not a token query string" \
  "https://api.github.com/repos/example/private-ckb/releases/assets/12345" \
  "$(ckb_clients_github_api_asset_url example/private-ckb 12345)"

# Token must never appear in constructed URLs.
TOKEN_SAMPLE="ghp_example_not_a_real_token_value"
url="$(ckb_clients_github_release_url nervosnetwork/ckb v0.209.0 ckb_v0.209.0_x86_64-unknown-linux-gnu-portable.tar.gz)"
if ckb_clients_url_contains_token "$url" "$TOKEN_SAMPLE"; then
  FAILS=$((FAILS + 1))
  echo "not ok - public release URL must not include a token"
else
  PASS=$((PASS + 1))
  echo "ok - public release URL must not include a token"
fi
api_url="$(ckb_clients_github_api_asset_url example/private-ckb 99)"
if ckb_clients_url_contains_token "$api_url" "$TOKEN_SAMPLE"; then
  FAILS=$((FAILS + 1))
  echo "not ok - API asset URL must not include a token"
else
  PASS=$((PASS + 1))
  echo "ok - API asset URL must not include a token"
fi

assert_ok "official ckb repo" ckb_clients_is_official_repo nervosnetwork/ckb
assert_ok "official light repo" ckb_clients_is_official_repo nervosnetwork/ckb-light-client
assert_fail "example private repo is not official" ckb_clients_is_official_repo example/private-ckb
assert_fail "invalid repo rejected" ckb_clients_validate_repo "../etc/passwd"
assert_fail "invalid source rejected" ckb_clients_validate_source nightly
assert_ok "release source allowed" ckb_clients_validate_source release
assert_ok "source mode allowed" ckb_clients_validate_source source
assert_ok "artifact mode allowed" ckb_clients_validate_source artifact

# --- default resolution from version files ---
unset CKB_REPO CKB_LIGHT_REPO CKB_SOURCE CKB_LIGHT_SOURCE CKB_REF CKB_LIGHT_REF
unset CKB_ARTIFACT_RUN_ID CKB_ARTIFACT_NAME CKB_LIGHT_ARTIFACT_RUN_ID CKB_LIGHT_ARTIFACT_NAME
unset UPLOAD_PACKAGES CKB_CLIENTS_SENSITIVE CKB_CLIENTS_SHOULD_UPLOAD
ckb_clients_load_defaults "$ROOT_DIR"
ckb_clients_validate_resolved
ckb_clients_export_upload_flags
assert_eq "default ckb repo" "nervosnetwork/ckb" "$CKB_REPO"
assert_eq "default light repo" "nervosnetwork/ckb-light-client" "$CKB_LIGHT_REPO"
assert_eq "default ckb source" "release" "$CKB_SOURCE"
assert_eq "default light source" "release" "$CKB_LIGHT_SOURCE"
assert_eq "default ckb ref from .ckb-version" "v0.209.0" "$CKB_REF"
assert_eq "default light ref from .ckb-light-version" "v0.5.4" "$CKB_LIGHT_REF"
assert_eq "default is not sensitive" "false" "$CKB_CLIENTS_SENSITIVE"
assert_eq "default should upload" "true" "$CKB_CLIENTS_SHOULD_UPLOAD"

# --- official develop source is public, so upload remains allowed ---
unset CKB_REPO CKB_LIGHT_REPO CKB_SOURCE CKB_LIGHT_SOURCE CKB_REF CKB_LIGHT_REF
CKB_LIGHT_SOURCE=source
CKB_LIGHT_REF=develop
ckb_clients_load_defaults "$ROOT_DIR"
ckb_clients_validate_resolved
ckb_clients_export_upload_flags
assert_eq "official develop source is not sensitive" "false" "$CKB_CLIENTS_SENSITIVE"
assert_eq "official develop source may upload" "true" "$CKB_CLIENTS_SHOULD_UPLOAD"
assert_eq "light ref develop preserved" "develop" "$CKB_LIGHT_REF"
assert_eq "light source source preserved" "source" "$CKB_LIGHT_SOURCE"

# --- non-official repo disables upload even if UPLOAD_PACKAGES=true ---
unset CKB_REPO CKB_LIGHT_REPO CKB_SOURCE CKB_LIGHT_SOURCE CKB_REF CKB_LIGHT_REF
CKB_REPO="example/private-ckb"
CKB_REF="develop"
UPLOAD_PACKAGES=true
ckb_clients_load_defaults "$ROOT_DIR"
ckb_clients_validate_resolved
ckb_clients_export_upload_flags
assert_eq "private ckb repo is sensitive" "true" "$CKB_CLIENTS_SENSITIVE"
assert_eq "private ckb repo must not upload packages" "false" "$CKB_CLIENTS_SHOULD_UPLOAD"

# explicit opt-out
unset CKB_REPO CKB_LIGHT_REPO CKB_SOURCE CKB_LIGHT_SOURCE CKB_REF CKB_LIGHT_REF
UPLOAD_PACKAGES=false
ckb_clients_load_defaults "$ROOT_DIR"
ckb_clients_validate_resolved
ckb_clients_export_upload_flags
assert_eq "upload packages false honored for official repos" "false" "$CKB_CLIENTS_SHOULD_UPLOAD"

# artifact validation
unset CKB_REPO CKB_LIGHT_REPO CKB_SOURCE CKB_LIGHT_SOURCE CKB_REF CKB_LIGHT_REF
unset CKB_ARTIFACT_RUN_ID CKB_ARTIFACT_NAME
CKB_SOURCE=artifact
ckb_clients_load_defaults "$ROOT_DIR"
assert_fail "artifact mode without run id / name fails" ckb_clients_validate_resolved
CKB_ARTIFACT_RUN_ID=123
CKB_ARTIFACT_NAME=ckb-linux
assert_ok "artifact mode with run id and name passes" ckb_clients_validate_resolved

# --- comment parsing ---
parsed="$(ckb_clients_parse_package_comment '/package --light-client-source source --light-client-ref develop')"
assert_eq "comment parse light source" "source" "$(printf '%s\n' "$parsed" | awk -F= '/^CKB_LIGHT_SOURCE=/{print $2}')"
assert_eq "comment parse light ref" "develop" "$(printf '%s\n' "$parsed" | awk -F= '/^CKB_LIGHT_REF=/{print $2}')"

parsed="$(ckb_clients_parse_package_comment '/package -test light_client_ref=develop ckb_source=release')"
assert_eq "comment parse -test flag" "true" "$(printf '%s\n' "$parsed" | awk -F= '/^PACKAGE_RUN_TEST=/{print $2}')"
assert_eq "comment parse key=value light ref" "develop" "$(printf '%s\n' "$parsed" | awk -F= '/^CKB_LIGHT_REF=/{print $2}')"
assert_eq "comment parse key=value ckb source" "release" "$(printf '%s\n' "$parsed" | awk -F= '/^CKB_SOURCE=/{print $2}')"

assert_fail "unknown comment flag fails" ckb_clients_parse_package_comment '/package --unknown-flag foo'

# --- resolve script end-to-end (defaults) ---
# Use a clean environment so earlier test exports do not leak in.
run_resolve() {
  (
    cd "$ROOT_DIR"
    env -u CKB_REPO -u CKB_LIGHT_REPO -u CKB_SOURCE -u CKB_LIGHT_SOURCE \
      -u CKB_REF -u CKB_LIGHT_REF -u CKB_ARTIFACT_RUN_ID -u CKB_ARTIFACT_NAME \
      -u CKB_LIGHT_ARTIFACT_RUN_ID -u CKB_LIGHT_ARTIFACT_NAME -u CKB_ASSET_NAME \
      -u CKB_LIGHT_ASSET_NAME -u UPLOAD_PACKAGES -u PACKAGE_COMMENT_BODY \
      -u INPUT_CKB_SOURCE -u INPUT_CKB_REPO -u INPUT_CKB_REF \
      -u INPUT_CKB_ARTIFACT_RUN_ID -u INPUT_CKB_ARTIFACT_NAME -u INPUT_CKB_ASSET_NAME \
      -u INPUT_LIGHT_CLIENT_SOURCE -u INPUT_LIGHT_CLIENT_REPO -u INPUT_LIGHT_CLIENT_REF \
      -u INPUT_LIGHT_CLIENT_ARTIFACT_RUN_ID -u INPUT_LIGHT_CLIENT_ARTIFACT_NAME \
      -u INPUT_LIGHT_CLIENT_ASSET_NAME -u INPUT_UPLOAD_PACKAGES \
      "$@" bash "$ROOT_DIR/scripts/resolve-ckb-client-env.sh"
  )
}

resolved="$(run_resolve 2>/tmp/ckb-clients-resolve-stderr.txt)"
assert_eq "resolve script default light ref" "v0.5.4" "$(printf '%s\n' "$resolved" | awk -F= '/^CKB_LIGHT_REF=/{print $2}')"
assert_eq "resolve script default upload" "true" "$(printf '%s\n' "$resolved" | awk -F= '/^CKB_CLIENTS_SHOULD_UPLOAD=/{print $2}')"
if grep -E 'ghp_|github_pat_|Bearer ' /tmp/ckb-clients-resolve-stderr.txt >/dev/null; then
  FAILS=$((FAILS + 1))
  echo "not ok - resolve script stderr leaked a token-like string"
else
  PASS=$((PASS + 1))
  echo "ok - resolve script stderr has no token-like string"
fi

# comment + input override via env
resolved="$(run_resolve PACKAGE_COMMENT_BODY='/package --light-client-source source --light-client-ref develop' 2>/tmp/ckb-clients-comment-stderr.txt)"
assert_eq "resolve script honors comment light ref" "develop" "$(printf '%s\n' "$resolved" | awk -F= '/^CKB_LIGHT_REF=/{print $2}')"
assert_eq "resolve script honors comment light source" "source" "$(printf '%s\n' "$resolved" | awk -F= '/^CKB_LIGHT_SOURCE=/{print $2}')"

resolved="$(run_resolve INPUT_CKB_REPO='example/private-ckb' INPUT_CKB_REF='heads/dev' INPUT_CKB_SOURCE='source' 2>/tmp/ckb-clients-sensitive-stderr.txt)"
assert_eq "resolve script marks non-official repo sensitive" "true" "$(printf '%s\n' "$resolved" | awk -F= '/^CKB_CLIENTS_SENSITIVE=/{print $2}')"
assert_eq "resolve script disables upload for non-official repo" "false" "$(printf '%s\n' "$resolved" | awk -F= '/^CKB_CLIENTS_SHOULD_UPLOAD=/{print $2}')"
if grep -F 'example/private-ckb' /tmp/ckb-clients-sensitive-stderr.txt >/dev/null; then
  FAILS=$((FAILS + 1))
  echo "not ok - sensitive plan should not print the non-official repo name"
else
  PASS=$((PASS + 1))
  echo "ok - sensitive plan does not print the non-official repo name"
fi

# --- manifest ---
export CKB_SOURCE=release CKB_REPO=nervosnetwork/ckb CKB_REF=v0.209.0 CKB_RESOLVED_SHA=deadbeef
export CKB_LIGHT_SOURCE=source CKB_LIGHT_REPO=nervosnetwork/ckb-light-client CKB_LIGHT_REF=develop
export CKB_LIGHT_RESOLVED_SHA=cafebabe CKB_CLIENTS_SENSITIVE=false CKB_CLIENTS_SHOULD_UPLOAD=true
export CKB_RESOLVED_ASSET=ckb_v0.209.0_x86_64-unknown-linux-gnu-portable.tar.gz
export CKB_RESOLVED_SHA256=abc CKB_LIGHT_RESOLVED_ASSET=source-build CKB_LIGHT_RESOLVED_SHA256=def
tmp_manifest="$(mktemp)"
ckb_clients_write_manifest "$tmp_manifest"
assert_eq "manifest light ref" "develop" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ckb_light_client"]["ref"])' "$tmp_manifest")"
assert_eq "manifest records resolved sha" "cafebabe" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ckb_light_client"]["resolved_sha"])' "$tmp_manifest")"
assert_eq "manifest ckb ref" "v0.209.0" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ckb"]["ref"])' "$tmp_manifest")"
rm -f "$tmp_manifest"

# --- live public URL check for default assets (no download of archives) ---
if command -v curl >/dev/null 2>&1; then
code_ckb="$(curl -sS -o /dev/null -w '%{http_code}' --max-redirs 0 --stderr /dev/null \
    "https://github.com/nervosnetwork/ckb/releases/download/v0.209.0/ckb_v0.209.0_x86_64-unknown-linux-gnu-portable.tar.gz" || true)"
  code_light="$(curl -sS -o /dev/null -w '%{http_code}' --max-redirs 0 --stderr /dev/null \
    "https://github.com/nervosnetwork/ckb-light-client/releases/download/v0.5.4/ckb-light-client_v0.5.4-x86_64-linux-portable.tar.gz" || true)"
  case "$code_ckb" in
    200|302) PASS=$((PASS + 1)); echo "ok - official ckb v0.209.0 linux asset exists ($code_ckb)" ;;
    *) FAILS=$((FAILS + 1)); echo "not ok - official ckb v0.209.0 linux asset http $code_ckb" ;;
  esac
  case "$code_light" in
    200|302) PASS=$((PASS + 1)); echo "ok - official light-client v0.5.4 linux asset exists ($code_light)" ;;
    *) FAILS=$((FAILS + 1)); echo "not ok - official light-client v0.5.4 linux asset http $code_light" ;;
  esac

  # A develop "release tag" should not exist.
  code_dev="$(curl -sS -o /dev/null -w '%{http_code}' --max-redirs 0 --stderr /dev/null \
    "https://github.com/nervosnetwork/ckb-light-client/releases/download/develop/ckb-light-client_develop-x86_64-linux-portable.tar.gz" || true)"
  case "$code_dev" in
    404) PASS=$((PASS + 1)); echo "ok - develop is not a light-client release tag (404)" ;;
    *) FAILS=$((FAILS + 1)); echo "not ok - expected 404 for develop release asset, got $code_dev" ;;
  esac
fi

echo
echo "Passed: $PASS  Failed: $FAILS"
if [ "$FAILS" -ne 0 ]; then
  exit 1
fi
