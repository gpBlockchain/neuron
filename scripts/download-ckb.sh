#!/usr/bin/env bash
# Obtain builtin CKB and ckb-light-client binaries for packaging.
# Default behavior is unchanged: download official public release assets
# named by .ckb-version and .ckb-light-version.
set -euo pipefail

ROOT_DIR="$(pwd)" # Be sure to run this from the repository root.
# shellcheck source=lib/ckb-clients.sh
. "$(dirname "$0")/lib/ckb-clients.sh"

ckb_clients_load_defaults "$ROOT_DIR"
ckb_clients_validate_resolved
ckb_clients_export_upload_flags
ckb_clients_log_plan

BUILD_WORKDIR="${TMPDIR:-/tmp}/neuron-ckb-clients-$$"
mkdir -p "$BUILD_WORKDIR"
cleanup() {
  rm -rf "$BUILD_WORKDIR"
}
trap cleanup EXIT

copy_light_configs() {
  local extracted_dir="$1"
  local dest_dir="$ROOT_DIR/packages/neuron-wallet/light"
  mkdir -p "$dest_dir"
  if [ -f "$extracted_dir/config/testnet.toml" ]; then
    cp "$extracted_dir/config/testnet.toml" "$dest_dir/ckb_light_testnet.toml"
    cp "$extracted_dir/config/mainnet.toml" "$dest_dir/ckb_light_mainnet.toml"
  elif [ -f "$extracted_dir/testnet.toml" ]; then
    cp "$extracted_dir/testnet.toml" "$dest_dir/ckb_light_testnet.toml"
    cp "$extracted_dir/mainnet.toml" "$dest_dir/ckb_light_mainnet.toml"
  else
    echo "light-client config files not found in $extracted_dir" >&2
    return 1
  fi
}

extract_archive() {
  local archive="$1"
  local dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.zip)
      unzip -q -o "$archive" -d "$dest"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$dest"
      ;;
    *)
      echo "Unsupported archive: $archive" >&2
      return 1
      ;;
  esac
}

find_one() {
  local dir="$1"
  shift
  local name
  for name in "$@"; do
    # Do not follow unexpected deep trees more than needed.
    found="$(find "$dir" -type f -name "$name" | head -n 1 || true)"
    if [ -n "$found" ]; then
      printf '%s' "$found"
      return 0
    fi
  done
  return 1
}

obtain_ckb_release() {
  local platform="$1"
  local arch="${2:-}"
  local dest_dir="$3"
  local dest_name="$4"
  local filename
  if [ -n "${CKB_ASSET_NAME:-}" ]; then
    filename="$CKB_ASSET_NAME"
  else
    filename="$(ckb_clients_ckb_asset_name "$platform" "$arch" "$CKB_REF")"
  fi
  local archive="$BUILD_WORKDIR/$filename"
  mkdir -p "$dest_dir"
  ckb_clients_download_release_asset "$CKB_REPO" "$CKB_REF" "$filename" "$archive"
  local extracted="$BUILD_WORKDIR/ckb-extract-${platform}${arch}"
  rm -rf "$extracted"
  extract_archive "$archive" "$extracted"
  local bin
  if [ "$platform" = "win" ]; then
    bin="$(find_one "$extracted" ckb.exe)"
  else
    bin="$(find_one "$extracted" ckb)"
  fi
  cp "$bin" "$dest_dir/$dest_name"
  chmod +x "$dest_dir/$dest_name" 2>/dev/null || true
  CKB_RESOLVED_ASSET="${CKB_RESOLVED_ASSET:+$CKB_RESOLVED_ASSET,}$filename"
  CKB_RESOLVED_SHA256="${CKB_RESOLVED_SHA256:+$CKB_RESOLVED_SHA256,}$(ckb_clients_sha256_file "$dest_dir/$dest_name")"
  export CKB_RESOLVED_ASSET CKB_RESOLVED_SHA256
}

obtain_light_release() {
  local platform="$1"
  local dest_dir="$2"
  local dest_name="$3"
  local filename
  if [ -n "${CKB_LIGHT_ASSET_NAME:-}" ]; then
    filename="$CKB_LIGHT_ASSET_NAME"
  else
    filename="$(ckb_clients_light_asset_name "$platform" "$CKB_LIGHT_REF")"
  fi
  local archive="$BUILD_WORKDIR/$filename"
  mkdir -p "$dest_dir"
  ckb_clients_download_release_asset "$CKB_LIGHT_REPO" "$CKB_LIGHT_REF" "$filename" "$archive"
  local extracted="$BUILD_WORKDIR/light-extract-${platform}"
  rm -rf "$extracted"
  extract_archive "$archive" "$extracted"
  local bin
  if [ "$platform" = "win" ]; then
    bin="$(find_one "$extracted" ckb-light-client.exe)"
  else
    bin="$(find_one "$extracted" ckb-light-client)"
  fi
  cp "$bin" "$dest_dir/$dest_name"
  chmod +x "$dest_dir/$dest_name" 2>/dev/null || true
  copy_light_configs "$extracted"
  CKB_LIGHT_RESOLVED_ASSET="$filename"
  CKB_LIGHT_RESOLVED_SHA256="$(ckb_clients_sha256_file "$dest_dir/$dest_name")"
  export CKB_LIGHT_RESOLVED_ASSET CKB_LIGHT_RESOLVED_SHA256
}

build_ckb_from_source() {
  local dest_dir="$1"
  local dest_name="$2"
  local target="${3:-}"
  local src="$BUILD_WORKDIR/ckb-src"
  if [ ! -d "$src/.git" ]; then
    ckb_clients_clone_ref "$CKB_REPO" "$CKB_REF" "$src"
    local token xtrace_was_on=0
    token="$(ckb_clients_token)"
    case "$-" in *x*) xtrace_was_on=1; set +x ;; esac
    if [ -n "$token" ]; then
      git -C "$src" -c "http.extraheader=AUTHORIZATION: bearer $token" submodule update --init --recursive
    else
      git -C "$src" submodule update --init --recursive
    fi
    [ "$xtrace_was_on" -eq 1 ] && set -x
  fi
  (
    cd "$src"
    if [ -n "$target" ]; then
      rustup target add "$target" >/dev/null
      export CKB_BUILD_TARGET="--target $target"
    fi
    if [ -f Makefile ] && grep -q '^prod_portable:' Makefile; then
      make prod_portable
    else
      cargo build --locked --bin ckb --release --features portable
    fi
  )
  local search="$src/target"
  local bin=""
  if [ -n "$target" ]; then
    bin="$(find_one "$search/$target" ckb ckb.exe || true)"
  fi
  if [ -z "$bin" ]; then
    bin="$(find_one "$search/prod" ckb ckb.exe || true)"
  fi
  if [ -z "$bin" ]; then
    bin="$(find_one "$search/release" ckb ckb.exe || true)"
  fi
  if [ -z "$bin" ]; then
    echo "CKB binary not found after source build" >&2
    return 1
  fi
  mkdir -p "$dest_dir"
  cp "$bin" "$dest_dir/$dest_name"
  chmod +x "$dest_dir/$dest_name" 2>/dev/null || true
  CKB_RESOLVED_SHA256="${CKB_RESOLVED_SHA256:+$CKB_RESOLVED_SHA256,}$(ckb_clients_sha256_file "$dest_dir/$dest_name")"
  CKB_RESOLVED_ASSET="${CKB_RESOLVED_ASSET:+$CKB_RESOLVED_ASSET,}source-build"
  export CKB_RESOLVED_SHA256 CKB_RESOLVED_ASSET
}

build_light_from_source() {
  local dest_dir="$1"
  local dest_name="$2"
  local src="$BUILD_WORKDIR/light-src"
  if [ ! -d "$src/.git" ]; then
    ckb_clients_clone_ref "$CKB_LIGHT_REPO" "$CKB_LIGHT_REF" "$src"
  fi
  (
    cd "$src"
    cargo build --release --features portable,vendored-openssl
  )
  local bin
  bin="$(find_one "$src/target/release" ckb-light-client ckb-light-client.exe)"
  mkdir -p "$dest_dir"
  cp "$bin" "$dest_dir/$dest_name"
  chmod +x "$dest_dir/$dest_name" 2>/dev/null || true
  copy_light_configs "$src"
  CKB_LIGHT_RESOLVED_ASSET="source-build"
  CKB_LIGHT_RESOLVED_SHA256="$(ckb_clients_sha256_file "$dest_dir/$dest_name")"
  export CKB_LIGHT_RESOLVED_ASSET CKB_LIGHT_RESOLVED_SHA256
}

copy_from_artifact() {
  local extracted="$1"
  local dest_dir="$2"
  local dest_name="$3"
  shift 3
  local bin
  bin="$(find_one "$extracted" "$@")"
  mkdir -p "$dest_dir"
  cp "$bin" "$dest_dir/$dest_name"
  chmod +x "$dest_dir/$dest_name" 2>/dev/null || true
  printf '%s' "$bin"
}

obtain_ckb() {
  local platform="$1"
  local dest_dir="$2"
  case "$CKB_SOURCE" in
    release)
      if [ "$platform" = "mac" ]; then
        obtain_ckb_release mac x86_64 "$dest_dir" ckb-x64
        obtain_ckb_release mac arm64 "$dest_dir" ckb-arm64
      elif [ "$platform" = "win" ]; then
        obtain_ckb_release win "" "$dest_dir" ckb.exe
      else
        obtain_ckb_release linux "" "$dest_dir" ckb
      fi
      ;;
    source)
      echo "Building CKB from source at $CKB_REF"
      if [ "$platform" = "mac" ]; then
        # Best-effort: native binary plus a cross target when rustup can add it.
        build_ckb_from_source "$dest_dir" ckb-x64 ""
        if rustup target list --installed 2>/dev/null | grep -q 'aarch64-apple-darwin' \
          || rustup target add aarch64-apple-darwin; then
          build_ckb_from_source "$dest_dir" ckb-arm64 aarch64-apple-darwin
        else
          echo "Cannot build aarch64 CKB on this runner; arm64 package would be incomplete." >&2
          return 1
        fi
        # If we are actually on arm64, the first untargeted build was arm64.
        # Detect and swap if needed.
        if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
          if [ -f "$dest_dir/ckb-x64" ] && [ -f "$dest_dir/ckb-arm64" ]; then
            mv "$dest_dir/ckb-x64" "$dest_dir/ckb-native-tmp"
            mv "$dest_dir/ckb-arm64" "$dest_dir/ckb-x64"
            mv "$dest_dir/ckb-native-tmp" "$dest_dir/ckb-arm64"
          fi
        fi
      elif [ "$platform" = "win" ]; then
        build_ckb_from_source "$dest_dir" ckb.exe ""
      else
        build_ckb_from_source "$dest_dir" ckb ""
      fi
      ;;
    artifact)
      echo "Downloading CKB Actions artifact"
      local extracted="$BUILD_WORKDIR/ckb-artifact"
      ckb_clients_download_actions_artifact "$CKB_REPO" "$CKB_ARTIFACT_RUN_ID" "$CKB_ARTIFACT_NAME" "$extracted"
      if [ "$platform" = "mac" ]; then
        copy_from_artifact "$extracted" "$dest_dir" ckb-x64 ckb-x64 ckb 'ckb_*x86_64*'
        copy_from_artifact "$extracted" "$dest_dir" ckb-arm64 ckb-arm64 'ckb_*aarch64*' 'ckb_*arm64*'
      elif [ "$platform" = "win" ]; then
        copy_from_artifact "$extracted" "$dest_dir" ckb.exe ckb.exe ckb
      else
        copy_from_artifact "$extracted" "$dest_dir" ckb ckb
      fi
      CKB_RESOLVED_ASSET="$CKB_ARTIFACT_NAME"
      export CKB_RESOLVED_ASSET
      ;;
  esac
}

obtain_light() {
  local platform="$1"
  local dest_dir="$2"
  case "$CKB_LIGHT_SOURCE" in
    release)
      if [ "$platform" = "win" ]; then
        obtain_light_release win "$dest_dir" ckb-light-client.exe
      else
        obtain_light_release "$platform" "$dest_dir" ckb-light-client
      fi
      ;;
    source)
      echo "Building ckb-light-client from source at $CKB_LIGHT_REF"
      if [ "$platform" = "win" ]; then
        build_light_from_source "$dest_dir" ckb-light-client.exe
      else
        build_light_from_source "$dest_dir" ckb-light-client
      fi
      ;;
    artifact)
      echo "Downloading ckb-light-client Actions artifact"
      local extracted="$BUILD_WORKDIR/light-artifact"
      ckb_clients_download_actions_artifact "$CKB_LIGHT_REPO" "$CKB_LIGHT_ARTIFACT_RUN_ID" "$CKB_LIGHT_ARTIFACT_NAME" "$extracted"
      if [ "$platform" = "win" ]; then
        copy_from_artifact "$extracted" "$dest_dir" ckb-light-client.exe ckb-light-client.exe ckb-light-client
      else
        copy_from_artifact "$extracted" "$dest_dir" ckb-light-client ckb-light-client
      fi
      if ! copy_light_configs "$extracted"; then
        bin_found="$(find_one "$extracted" ckb-light-client ckb-light-client.exe)"
        copy_light_configs "$(dirname "$bin_found")"
      fi
      CKB_LIGHT_RESOLVED_ASSET="$CKB_LIGHT_ARTIFACT_NAME"
      export CKB_LIGHT_RESOLVED_ASSET
      ;;
  esac
}

resolve_source_shas() {
  # Best-effort; source/artifact modes should record the commit when the API allows it.
  # Official public release tags also resolve.
  if CKB_RESOLVED_SHA="$(ckb_clients_resolve_sha "$CKB_REPO" "$CKB_REF" 2>/dev/null)"; then
    export CKB_RESOLVED_SHA
  else
    CKB_RESOLVED_SHA=""
    export CKB_RESOLVED_SHA
  fi
  if CKB_LIGHT_RESOLVED_SHA="$(ckb_clients_resolve_sha "$CKB_LIGHT_REPO" "$CKB_LIGHT_REF" 2>/dev/null)"; then
    export CKB_LIGHT_RESOLVED_SHA
  else
    CKB_LIGHT_RESOLVED_SHA=""
    export CKB_LIGHT_RESOLVED_SHA
  fi
}

PLATFORM_ARG="${1:-}"
case "$PLATFORM_ARG" in
  mac)
    obtain_ckb mac "$ROOT_DIR/packages/neuron-wallet/bin/mac"
    obtain_light mac "$ROOT_DIR/packages/neuron-wallet/bin/mac"
    ;;
  linux)
    obtain_ckb linux "$ROOT_DIR/packages/neuron-wallet/bin/linux"
    obtain_light linux "$ROOT_DIR/packages/neuron-wallet/bin/linux"
    ;;
  win)
    obtain_ckb win "$ROOT_DIR/packages/neuron-wallet/bin/win"
    obtain_light win "$ROOT_DIR/packages/neuron-wallet/bin/win"
    ;;
  *)
    if [ "${OSTYPE:-}" = "darwin"* ] || [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
      obtain_ckb mac "$ROOT_DIR/packages/neuron-wallet/bin/mac"
      obtain_light mac "$ROOT_DIR/packages/neuron-wallet/bin/mac"
    elif [ "${OSTYPE:-}" = "linux-gnu" ] || [ "$(uname -s 2>/dev/null || true)" = "Linux" ]; then
      obtain_ckb linux "$ROOT_DIR/packages/neuron-wallet/bin/linux"
      obtain_light linux "$ROOT_DIR/packages/neuron-wallet/bin/linux"
    else
      obtain_ckb win "$ROOT_DIR/packages/neuron-wallet/bin/win"
      obtain_light win "$ROOT_DIR/packages/neuron-wallet/bin/win"
    fi
    ;;
esac

resolve_source_shas || true
MANIFEST_PATH="$ROOT_DIR/ckb-clients-manifest.json"
ckb_clients_write_manifest "$MANIFEST_PATH"
echo "Wrote $MANIFEST_PATH"
