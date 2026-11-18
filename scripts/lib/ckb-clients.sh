#!/usr/bin/env bash
# Helpers for resolving and obtaining builtin CKB / ckb-light-client binaries.
# Credentials must only travel via headers or GH_TOKEN/env; never put tokens in URLs or logs.

CKB_CLIENTS_OFFICIAL_CKB_REPO="nervosnetwork/ckb"
CKB_CLIENTS_OFFICIAL_LIGHT_REPO="nervosnetwork/ckb-light-client"
CKB_CLIENTS_VALID_SOURCES="release source artifact"
CKB_CLIENTS_LIB_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ckb_clients_trim() {
  printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ckb_clients_token() {
  # Preferred secret name is NEURON_DEP_GITHUB_TOKEN; CKB_CLIENT_TOKEN is an alias.
  if [ -n "${CKB_CLIENT_TOKEN:-}" ]; then
    printf '%s' "$CKB_CLIENT_TOKEN"
  else
    printf '%s' "${NEURON_DEP_GITHUB_TOKEN:-}"
  fi
}

ckb_clients_is_official_repo() {
  local repo
  repo="$(ckb_clients_trim "$1")"
  [ "$repo" = "$CKB_CLIENTS_OFFICIAL_CKB_REPO" ] || [ "$repo" = "$CKB_CLIENTS_OFFICIAL_LIGHT_REPO" ]
}

ckb_clients_validate_repo() {
  local repo
  repo="$(ckb_clients_trim "$1")"
  printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
}

ckb_clients_validate_source() {
  local source
  source="$(ckb_clients_trim "$1")"
  [ "$source" = "release" ] || [ "$source" = "source" ] || [ "$source" = "artifact" ]
}

ckb_clients_is_sensitive() {
  local ckb_repo light_repo
  ckb_repo="$(ckb_clients_trim "${1:-}")"
  light_repo="$(ckb_clients_trim "${2:-}")"
  if ! ckb_clients_is_official_repo "$ckb_repo"; then
    return 0
  fi
  if ! ckb_clients_is_official_repo "$light_repo"; then
    return 0
  fi
  return 1
}

ckb_clients_should_upload_packages() {
  local upload_flag="$1"
  local ckb_repo="$2"
  local light_repo="$3"
  upload_flag="$(ckb_clients_trim "$upload_flag")"
  if [ "$upload_flag" = "false" ] || [ "$upload_flag" = "False" ] || [ "$upload_flag" = "0" ]; then
    return 1
  fi
  if ckb_clients_is_sensitive "$ckb_repo" "$light_repo"; then
    return 1
  fi
  return 0
}

ckb_clients_github_release_url() {
  local repo ref filename
  repo="$(ckb_clients_trim "$1")"
  ref="$(ckb_clients_trim "$2")"
  filename="$(ckb_clients_trim "$3")"
  printf 'https://github.com/%s/releases/download/%s/%s' "$repo" "$ref" "$filename"
}

ckb_clients_github_api_asset_url() {
  local repo asset_id
  repo="$(ckb_clients_trim "$1")"
  asset_id="$(ckb_clients_trim "$2")"
  printf 'https://api.github.com/repos/%s/releases/assets/%s' "$repo" "$asset_id"
}

ckb_clients_github_api_release_url() {
  local repo ref
  repo="$(ckb_clients_trim "$1")"
  ref="$(ckb_clients_trim "$2")"
  printf 'https://api.github.com/repos/%s/releases/tags/%s' "$repo" "$ref"
}

ckb_clients_github_api_commit_url() {
  local repo ref
  repo="$(ckb_clients_trim "$1")"
  ref="$(ckb_clients_trim "$2")"
  # Encode only spaces; refs are tags, branches, or SHAs.
  printf 'https://api.github.com/repos/%s/commits/%s' "$repo" "$ref"
}

ckb_clients_ckb_asset_name() {
  local platform="$1"
  local arch="${2:-}"
  local ref="$3"
  case "$platform" in
    linux)
      printf 'ckb_%s_x86_64-unknown-linux-gnu-portable.tar.gz' "$ref"
      ;;
    win)
      printf 'ckb_%s_x86_64-pc-windows-msvc.zip' "$ref"
      ;;
    mac)
      if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
        printf 'ckb_%s_aarch64-apple-darwin-portable.zip' "$ref"
      else
        printf 'ckb_%s_x86_64-apple-darwin-portable.zip' "$ref"
      fi
      ;;
    *)
      echo "Unknown CKB platform: $platform" >&2
      return 1
      ;;
  esac
}

ckb_clients_light_asset_name() {
  local platform="$1"
  local ref="$2"
  case "$platform" in
    linux)
      printf 'ckb-light-client_%s-x86_64-linux-portable.tar.gz' "$ref"
      ;;
    win)
      printf 'ckb-light-client_%s-x86_64-windows.tar.gz' "$ref"
      ;;
    mac)
      printf 'ckb-light-client_%s-x86_64-darwin-portable.tar.gz' "$ref"
      ;;
    *)
      echo "Unknown light-client platform: $platform" >&2
      return 1
      ;;
  esac
}

# Return 0 if a string looks like it contains a secret value (for tests / guards).
ckb_clients_url_contains_token() {
  local url="$1"
  local token="$2"
  [ -n "$token" ] && printf '%s' "$url" | grep -Fq "$token"
}

ckb_clients_read_version_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "Missing version file: $path" >&2
    return 1
  fi
  ckb_clients_trim "$(head -n 1 "$path")"
}

# Parse /package comment flags into "KEY=VALUE" lines on stdout.
# Supports:
#   /package
#   /package -test
#   /package --light-client-ref develop --light-client-source source
#   /package light_client_ref=develop
ckb_clients_parse_package_comment() {
  local body="$1"
  body="$(printf '%s' "$body" | tr -d '\r')"
  # Normalize newlines to spaces so flags can wrap.
  body="$(printf '%s' "$body" | tr '\n' ' ')"
  body="$(ckb_clients_trim "$body")"

  case "$body" in
    /package*)
      ;;
    *)
      return 0
      ;;
  esac

  # Drop the leading /package and optional -test token.
  local rest
  rest="$(ckb_clients_trim "${body#/package}")"
  case "$rest" in
    -test*)
      rest="$(ckb_clients_trim "${rest#-test}")"
      echo "PACKAGE_RUN_TEST=true"
      ;;
  esac

  # shellcheck disable=SC2086
  # Parse remaining tokens. Use a simple loop over words, allowing --key value and key=value.
  local token key value next
  # We'll iterate with a temp string.
  while [ -n "$(ckb_clients_trim "$rest")" ]; do
    rest="$(ckb_clients_trim "$rest")"
    token="${rest%% *}"
    if [ "$token" = "$rest" ]; then
      rest=""
    else
      rest="$(ckb_clients_trim "${rest#"$token"}")"
    fi

    case "$token" in
      --ckb-source|--ckb-repo|--ckb-ref|--ckb-url|--ckb-artifact-run-id|--ckb-artifact-name|--ckb-asset-name|--light-client-source|--light-client-repo|--light-client-ref|--light-client-url|--light-client-artifact-run-id|--light-client-artifact-name|--light-client-asset-name|--upload-packages)
        key="$token"
        next="${rest%% *}"
        if [ -z "$next" ] || [ "$next" = "$rest" ] && [ -z "$rest" ]; then
          echo "Missing value for $key" >&2
          return 1
        fi
        if [ "$next" = "$rest" ]; then
          value="$rest"
          rest=""
        else
          value="$next"
          rest="$(ckb_clients_trim "${rest#"$next"}")"
        fi
        ckb_clients_emit_flag "$key" "$value" || return 1
        ;;
      --*=*)
        key="${token%%=*}"
        value="${token#*=}"
        ckb_clients_emit_flag "$key" "$value" || return 1
        ;;
      *=*)
        key="${token%%=*}"
        value="${token#*=}"
        ckb_clients_emit_flag "$key" "$value" || return 1
        ;;
      -test)
        echo "PACKAGE_RUN_TEST=true"
        ;;
      *)
        echo "Unknown /package argument: $token" >&2
        return 1
        ;;
    esac
  done
}

ckb_clients_emit_flag() {
  local key value envname
  key="$(ckb_clients_trim "$1")"
  value="$(ckb_clients_trim "$2")"
  case "$key" in
    --ckb-source|ckb-source|ckb_source) envname="CKB_SOURCE" ;;
    --ckb-repo|ckb-repo|ckb_repo) envname="CKB_REPO" ;;
    --ckb-ref|ckb-ref|ckb_ref) envname="CKB_REF" ;;
    --ckb-url|ckb-url|ckb_url) envname="CKB_URL" ;;
    --ckb-artifact-run-id|ckb-artifact-run-id|ckb_artifact_run_id) envname="CKB_ARTIFACT_RUN_ID" ;;
    --ckb-artifact-name|ckb-artifact-name|ckb_artifact_name) envname="CKB_ARTIFACT_NAME" ;;
    --ckb-asset-name|ckb-asset-name|ckb_asset_name) envname="CKB_ASSET_NAME" ;;
    --light-client-source|light-client-source|light_client_source) envname="CKB_LIGHT_SOURCE" ;;
    --light-client-repo|light-client-repo|light_client_repo) envname="CKB_LIGHT_REPO" ;;
    --light-client-ref|light-client-ref|light_client_ref) envname="CKB_LIGHT_REF" ;;
    --light-client-url|light-client-url|light_client_url) envname="CKB_LIGHT_URL" ;;
    --light-client-artifact-run-id|light-client-artifact-run-id|light_client_artifact_run_id) envname="CKB_LIGHT_ARTIFACT_RUN_ID" ;;
    --light-client-artifact-name|light-client-artifact-name|light_client_artifact_name) envname="CKB_LIGHT_ARTIFACT_NAME" ;;
    --light-client-asset-name|light-client-asset-name|light_client_asset_name) envname="CKB_LIGHT_ASSET_NAME" ;;
    --upload-packages|upload-packages|upload_packages) envname="UPLOAD_PACKAGES" ;;
    *)
      echo "Unknown /package argument: $key" >&2
      return 1
      ;;
  esac
  printf '%s=%s\n' "$envname" "$value"
}

ckb_clients_apply_assignments() {
  # Read KEY=VALUE lines and export them.
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(ckb_clients_trim "$line")"
    [ -z "$line" ] && continue
    key="${line%%=*}"
    value="${line#*=}"
    export "$key=$value"
  done
}


# Parse a GitHub releases/tag or tree URL. Prints MODE=, REPO=, REF= lines.
ckb_clients_parse_github_url() {
  python3 "$CKB_CLIENTS_LIB_DIR/parse-github-client-url.py" "$1"
}

# Apply a parsed URL to CKB_* or CKB_LIGHT_* variables.
# If repo/ref/source are already set, they must match the URL; conflicts are
# rejected rather than silently overridden.
# $1 = CKB | CKB_LIGHT
# $2 = URL (empty is a no-op)
ckb_clients_apply_github_url() {
  local prefix="$1"
  local url="$2"
  local parsed line key value
  local url_mode url_repo url_ref
  local cur_mode cur_repo cur_ref

  url="$(ckb_clients_trim "$url")"
  [ -z "$url" ] && return 0

  parsed="$(ckb_clients_parse_github_url "$url")" || return 1
  url_mode=""
  url_repo=""
  url_ref=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(ckb_clients_trim "$line")"
    [ -z "$line" ] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      MODE) url_mode="$value" ;;
      REPO) url_repo="$value" ;;
      REF) url_ref="$value" ;;
    esac
  done <<EOF
$parsed
EOF

  if [ -z "$url_mode" ] || [ -z "$url_repo" ] || [ -z "$url_ref" ]; then
    echo "Failed to parse GitHub URL" >&2
    return 1
  fi

  if [ "$prefix" = "CKB_LIGHT" ]; then
    cur_mode="${CKB_LIGHT_SOURCE:-}"
    cur_repo="${CKB_LIGHT_REPO:-}"
    cur_ref="${CKB_LIGHT_REF:-}"
  else
    cur_mode="${CKB_SOURCE:-}"
    cur_repo="${CKB_REPO:-}"
    cur_ref="${CKB_REF:-}"
  fi

  if [ -n "$cur_mode" ] && [ "$cur_mode" != "$url_mode" ]; then
    echo "Conflicting ${prefix} source: existing ${cur_mode} vs URL ${url_mode}" >&2
    return 1
  fi
  if [ -n "$cur_repo" ] && [ "$cur_repo" != "$url_repo" ]; then
    echo "Conflicting ${prefix} repo: existing value does not match the URL" >&2
    return 1
  fi
  if [ -n "$cur_ref" ] && [ "$cur_ref" != "$url_ref" ]; then
    echo "Conflicting ${prefix} ref: existing ${cur_ref} vs URL ${url_ref}" >&2
    return 1
  fi

  if [ "$prefix" = "CKB_LIGHT" ]; then
    CKB_LIGHT_SOURCE="$url_mode"
    CKB_LIGHT_REPO="$url_repo"
    CKB_LIGHT_REF="$url_ref"
    export CKB_LIGHT_SOURCE CKB_LIGHT_REPO CKB_LIGHT_REF
  else
    CKB_SOURCE="$url_mode"
    CKB_REPO="$url_repo"
    CKB_REF="$url_ref"
    export CKB_SOURCE CKB_REPO CKB_REF
  fi
}

ckb_clients_load_defaults() {
  local root_dir="${1:-.}"
  if [ -z "${CKB_REPO:-}" ]; then
    CKB_REPO="$CKB_CLIENTS_OFFICIAL_CKB_REPO"
  fi
  if [ -z "${CKB_LIGHT_REPO:-}" ]; then
    CKB_LIGHT_REPO="$CKB_CLIENTS_OFFICIAL_LIGHT_REPO"
  fi
  if [ -z "${CKB_SOURCE:-}" ]; then
    CKB_SOURCE="release"
  fi
  if [ -z "${CKB_LIGHT_SOURCE:-}" ]; then
    CKB_LIGHT_SOURCE="release"
  fi
  if [ -z "${CKB_REF:-}" ]; then
    CKB_REF="$(ckb_clients_read_version_file "$root_dir/.ckb-version")"
  fi
  if [ -z "${CKB_LIGHT_REF:-}" ]; then
    CKB_LIGHT_REF="$(ckb_clients_read_version_file "$root_dir/.ckb-light-version")"
  fi
  CKB_REPO="$(ckb_clients_trim "$CKB_REPO")"
  CKB_LIGHT_REPO="$(ckb_clients_trim "$CKB_LIGHT_REPO")"
  CKB_SOURCE="$(ckb_clients_trim "$CKB_SOURCE")"
  CKB_LIGHT_SOURCE="$(ckb_clients_trim "$CKB_LIGHT_SOURCE")"
  CKB_REF="$(ckb_clients_trim "$CKB_REF")"
  CKB_LIGHT_REF="$(ckb_clients_trim "$CKB_LIGHT_REF")"
  export CKB_REPO CKB_LIGHT_REPO CKB_SOURCE CKB_LIGHT_SOURCE CKB_REF CKB_LIGHT_REF
}

ckb_clients_validate_resolved() {
  if ! ckb_clients_validate_repo "$CKB_REPO"; then
    echo "Invalid CKB_REPO: $CKB_REPO" >&2
    return 1
  fi
  if ! ckb_clients_validate_repo "$CKB_LIGHT_REPO"; then
    echo "Invalid CKB_LIGHT_REPO: $CKB_LIGHT_REPO" >&2
    return 1
  fi
  if ! ckb_clients_validate_source "$CKB_SOURCE"; then
    echo "Invalid CKB_SOURCE: $CKB_SOURCE (expected release, source, or artifact)" >&2
    return 1
  fi
  if ! ckb_clients_validate_source "$CKB_LIGHT_SOURCE"; then
    echo "Invalid CKB_LIGHT_SOURCE: $CKB_LIGHT_SOURCE (expected release, source, or artifact)" >&2
    return 1
  fi
  if [ -z "$CKB_REF" ]; then
    echo "CKB_REF is empty" >&2
    return 1
  fi
  if [ -z "$CKB_LIGHT_REF" ]; then
    echo "CKB_LIGHT_REF is empty" >&2
    return 1
  fi
  if [ "$CKB_SOURCE" = "artifact" ]; then
    if [ -z "${CKB_ARTIFACT_RUN_ID:-}" ] || [ -z "${CKB_ARTIFACT_NAME:-}" ]; then
      echo "CKB_SOURCE=artifact requires CKB_ARTIFACT_RUN_ID and CKB_ARTIFACT_NAME" >&2
      return 1
    fi
  fi
  if [ "$CKB_LIGHT_SOURCE" = "artifact" ]; then
    if [ -z "${CKB_LIGHT_ARTIFACT_RUN_ID:-}" ] || [ -z "${CKB_LIGHT_ARTIFACT_NAME:-}" ]; then
      echo "CKB_LIGHT_SOURCE=artifact requires CKB_LIGHT_ARTIFACT_RUN_ID and CKB_LIGHT_ARTIFACT_NAME" >&2
      return 1
    fi
  fi
}

ckb_clients_export_upload_flags() {
  if ckb_clients_is_sensitive "$CKB_REPO" "$CKB_LIGHT_REPO"; then
    CKB_CLIENTS_SENSITIVE="true"
  else
    CKB_CLIENTS_SENSITIVE="false"
  fi
  if ckb_clients_should_upload_packages "${UPLOAD_PACKAGES:-true}" "$CKB_REPO" "$CKB_LIGHT_REPO"; then
    CKB_CLIENTS_SHOULD_UPLOAD="true"
  else
    CKB_CLIENTS_SHOULD_UPLOAD="false"
  fi
  export CKB_CLIENTS_SENSITIVE CKB_CLIENTS_SHOULD_UPLOAD
}

# HTTP helpers. Always disable xtrace around token use.
ckb_clients_curl() {
  local token xtrace_was_on=0
  token="$(ckb_clients_token)"
  case "$-" in *x*) xtrace_was_on=1; set +x ;; esac
  if [ -n "$token" ]; then
    curl -sS -L -H "Authorization: Bearer ${token}" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
    local st=$?
    [ "$xtrace_was_on" -eq 1 ] && set -x
    return $st
  fi
  curl -sS -L -H "X-GitHub-Api-Version: 2022-11-28" "$@"
  local st=$?
  [ "$xtrace_was_on" -eq 1 ] && set -x
  return $st
}

ckb_clients_resolve_sha() {
  local repo ref url json sha
  repo="$(ckb_clients_trim "$1")"
  ref="$(ckb_clients_trim "$2")"
  url="$(ckb_clients_github_api_commit_url "$repo" "$ref")"
  json="$(ckb_clients_curl -H "Accept: application/vnd.github+json" "$url")" || return 1
  sha="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha") or "")')"
  if [ -z "$sha" ]; then
    echo "Failed to resolve SHA for $repo@$ref" >&2
    return 1
  fi
  printf '%s' "$sha"
}

ckb_clients_download_release_asset() {
  local repo ref filename dest
  repo="$(ckb_clients_trim "$1")"
  ref="$(ckb_clients_trim "$2")"
  filename="$(ckb_clients_trim "$3")"
  dest="$(ckb_clients_trim "$4")"
  local token
  token="$(ckb_clients_token)"

  if [ -n "$token" ]; then
    local release_url release_json asset_id asset_url
    release_url="$(ckb_clients_github_api_release_url "$repo" "$ref")"
    release_json="$(ckb_clients_curl -H "Accept: application/vnd.github+json" "$release_url")" || return 1
    asset_id="$(printf '%s' "$release_json" | FILENAME="$filename" python3 -c '
import json,os,sys
name=os.environ["FILENAME"]
data=json.load(sys.stdin)
assets=data.get("assets") or []
for a in assets:
    if a.get("name")==name:
        print(a.get("id") or "")
        break
')"
    if [ -z "$asset_id" ]; then
      echo "Release asset not found: $filename in $repo@$ref" >&2
      return 1
    fi
    asset_url="$(ckb_clients_github_api_asset_url "$repo" "$asset_id")"
    ckb_clients_curl -H "Accept: application/octet-stream" -o "$dest" "$asset_url" || return 1
  else
    local browser_url
    browser_url="$(ckb_clients_github_release_url "$repo" "$ref" "$filename")"
    # Public download; still no token in the URL.
    curl -sS -L -o "$dest" "$browser_url" || return 1
  fi

  if [ ! -s "$dest" ]; then
    echo "Downloaded asset is empty: $filename" >&2
    return 1
  fi
}

ckb_clients_clone_ref() {
  local repo ref dest
  repo="$(ckb_clients_trim "$1")"
  ref="$(ckb_clients_trim "$2")"
  dest="$(ckb_clients_trim "$3")"
  local token xtrace_was_on=0
  token="$(ckb_clients_token)"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  case "$-" in *x*) xtrace_was_on=1; set +x ;; esac
  if [ -n "$token" ]; then
    # extraheader keeps the token out of the remote URL and git logs.
    git -c "http.extraheader=AUTHORIZATION: bearer $token" clone --depth 1 --branch "$ref" "https://github.com/${repo}.git" "$dest"
    local st=$?
    if [ $st -ne 0 ]; then
      # Some SHAs cannot be used with --branch; fetch the commit instead.
      git -c "http.extraheader=AUTHORIZATION: bearer $token" clone --depth 1 "https://github.com/${repo}.git" "$dest" \
        && git -C "$dest" -c "http.extraheader=AUTHORIZATION: bearer $token" fetch --depth 1 origin "$ref" \
        && git -C "$dest" checkout FETCH_HEAD
      st=$?
    fi
    [ "$xtrace_was_on" -eq 1 ] && set -x
    return $st
  fi
  git clone --depth 1 --branch "$ref" "https://github.com/${repo}.git" "$dest"
  local st=$?
  if [ $st -ne 0 ]; then
    git clone --depth 1 "https://github.com/${repo}.git" "$dest" \
      && git -C "$dest" fetch --depth 1 origin "$ref" \
      && git -C "$dest" checkout FETCH_HEAD
    st=$?
  fi
  [ "$xtrace_was_on" -eq 1 ] && set -x
  return $st
}

ckb_clients_download_actions_artifact() {
  local repo run_id name dest
  repo="$(ckb_clients_trim "$1")"
  run_id="$(ckb_clients_trim "$2")"
  name="$(ckb_clients_trim "$3")"
  dest="$(ckb_clients_trim "$4")"
  local token xtrace_was_on=0
  token="$(ckb_clients_token)"
  rm -rf "$dest"
  mkdir -p "$dest"
  case "$-" in *x*) xtrace_was_on=1; set +x ;; esac
  if [ -n "$token" ]; then
    GH_TOKEN="$token" gh run download "$run_id" --repo "$repo" --name "$name" --dir "$dest"
  else
    gh run download "$run_id" --repo "$repo" --name "$name" --dir "$dest"
  fi
  local st=$?
  [ "$xtrace_was_on" -eq 1 ] && set -x
  return $st
}

ckb_clients_sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

ckb_clients_write_manifest() {
  local dest="$1"
  python3 - "$dest" <<'PY'
import json, os, sys
dest = sys.argv[1]
manifest = {
  "ckb": {
    "source": os.environ.get("CKB_SOURCE", ""),
    "repo": os.environ.get("CKB_REPO", ""),
    "ref": os.environ.get("CKB_REF", ""),
    "resolved_sha": os.environ.get("CKB_RESOLVED_SHA", ""),
    "asset": os.environ.get("CKB_RESOLVED_ASSET", ""),
    "sha256": os.environ.get("CKB_RESOLVED_SHA256", ""),
  },
  "ckb_light_client": {
    "source": os.environ.get("CKB_LIGHT_SOURCE", ""),
    "repo": os.environ.get("CKB_LIGHT_REPO", ""),
    "ref": os.environ.get("CKB_LIGHT_REF", ""),
    "resolved_sha": os.environ.get("CKB_LIGHT_RESOLVED_SHA", ""),
    "asset": os.environ.get("CKB_LIGHT_RESOLVED_ASSET", ""),
    "sha256": os.environ.get("CKB_LIGHT_RESOLVED_SHA256", ""),
  },
  "sensitive": os.environ.get("CKB_CLIENTS_SENSITIVE", "false") == "true",
  "uploaded_packages": os.environ.get("CKB_CLIENTS_SHOULD_UPLOAD", "false") == "true",
}
# If sources are sensitive, still record origin locally for the operator,
# but callers must not upload this file from a public repository.
os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
}

ckb_clients_log_plan() {
  # Safe summary: never print tokens. For non-official repos, avoid echoing the exact repo
  # in case this is running on a public Actions log.
  if [ "${CKB_CLIENTS_SENSITIVE:-false}" = "true" ]; then
    echo "Client sources include a non-official repository; package upload will be skipped."
    echo "CKB mode=${CKB_SOURCE} ref=${CKB_REF}"
    echo "Light client mode=${CKB_LIGHT_SOURCE} ref=${CKB_LIGHT_REF}"
  else
    echo "CKB ${CKB_SOURCE} ${CKB_REPO}@${CKB_REF}"
    echo "Light client ${CKB_LIGHT_SOURCE} ${CKB_LIGHT_REPO}@${CKB_LIGHT_REF}"
  fi
  echo "Upload packages: ${CKB_CLIENTS_SHOULD_UPLOAD:-unknown}"
}
