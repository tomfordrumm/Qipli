#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || fail "usage: $0 vX.Y.Z output-appcast.xml"
release_tag="$1"
output_path="$2"
: "${QIPLI_SPARKLE_PRIVATE_KEY:?QIPLI_SPARKLE_PRIVATE_KEY is required}"

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
version_file="$repository_root/Config/Version.xcconfig"
version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
archive_name="Qipli-$version.zip"
archive_path="$repository_root/dist/$archive_name"
[[ -f "$archive_path" ]] || fail "release archive does not exist: $archive_path"

generate_appcast="${QIPLI_SPARKLE_GENERATE_APPCAST:-$repository_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
sign_update="${QIPLI_SPARKLE_SIGN_UPDATE:-$repository_root/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
[[ -x "$generate_appcast" ]] || fail "Sparkle generate_appcast tool is unavailable"
[[ -x "$sign_update" ]] || fail "Sparkle sign_update tool is unavailable"

work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/qipli-appcast.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT INT TERM
cp "$archive_path" "$work_dir/$archive_name"
mkdir -p "$(dirname "$output_path")"

repository="${GITHUB_REPOSITORY:-tomfordrumm/Qipli}"
download_prefix="https://github.com/$repository/releases/download/$release_tag/"
printf '%s' "$QIPLI_SPARKLE_PRIVATE_KEY" \
    | "$generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "$download_prefix" \
        --maximum-versions 1 \
        --maximum-deltas 0 \
        -o "$output_path" \
        "$work_dir"

QIPLI_SPARKLE_SIGN_UPDATE="$sign_update" \
    "$script_dir/verify-sparkle-appcast.sh" \
        --tag "$release_tag" \
        --archive "$archive_path" \
        --appcast "$output_path"

echo "Prepared signed Sparkle appcast: $output_path"
