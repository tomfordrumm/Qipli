#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    fail "usage: $0 --tag vX.Y.Z --archive path --appcast path [--require-public]"
}

release_tag=""
archive_path=""
appcast_path=""
require_public=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            [[ $# -ge 2 ]] || usage
            release_tag="$2"
            shift 2
            ;;
        --archive)
            [[ $# -ge 2 ]] || usage
            archive_path="$2"
            shift 2
            ;;
        --appcast)
            [[ $# -ge 2 ]] || usage
            appcast_path="$2"
            shift 2
            ;;
        --require-public)
            require_public=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

[[ -n "$release_tag" && -n "$archive_path" && -n "$appcast_path" ]] || usage
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid stable tag: $release_tag"
[[ -f "$archive_path" ]] || fail "archive does not exist: $archive_path"
[[ -f "$appcast_path" ]] || fail "appcast does not exist: $appcast_path"
command -v xmllint >/dev/null || fail "xmllint is required"

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
version_file="$repository_root/Config/Version.xcconfig"
version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
build_number=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
[[ "$release_tag" == "v$version" ]] || fail "tag $release_tag does not match marketing version $version"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "build number must be a positive integer"

xmllint --noout "$appcast_path"
item_count=$(xmllint --xpath 'count(/rss/channel/item)' "$appcast_path")
[[ "$item_count" == "1" ]] || fail "stable appcast must contain exactly one update item"

read_attribute() {
    local attribute="$1"
    xmllint --xpath "string(/rss/channel/item/enclosure/@*[local-name()='$attribute'])" "$appcast_path"
}

read_element() {
    local element="$1"
    xmllint --xpath "string(/rss/channel/item/*[local-name()='$element'])" "$appcast_path"
}

archive_name=$(basename "$archive_path")
repository="${GITHUB_REPOSITORY:-tomfordrumm/Qipli}"
expected_url="https://github.com/$repository/releases/download/$release_tag/$archive_name"
actual_url=$(read_attribute url)
actual_build=$(read_element version)
actual_version=$(read_element shortVersionString)
minimum_system_version=$(read_element minimumSystemVersion)
signature=$(read_attribute edSignature)
declared_length=$(read_attribute length)
actual_length=$(stat -f '%z' "$archive_path")

[[ "$actual_url" == "$expected_url" ]] || fail "appcast archive URL is not the immutable release asset URL"
[[ "$actual_build" == "$build_number" ]] || fail "appcast build $actual_build does not match $build_number"
[[ "$actual_version" == "$version" ]] || fail "appcast version $actual_version does not match $version"
[[ "$minimum_system_version" == "14.0" ]] || fail "appcast minimum macOS must be 14.0"
[[ -n "$signature" ]] || fail "appcast enclosure is missing an EdDSA signature"
[[ "$declared_length" == "$actual_length" ]] || fail "appcast archive length does not match the release asset"

if [[ -n "${QIPLI_SPARKLE_PRIVATE_KEY:-}" ]]; then
    sign_update="${QIPLI_SPARKLE_SIGN_UPDATE:-$repository_root/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
    [[ -x "$sign_update" ]] || fail "Sparkle sign_update tool is unavailable"
    printf '%s' "$QIPLI_SPARKLE_PRIVATE_KEY" \
        | "$sign_update" --verify --ed-key-file - "$archive_path" "$signature" >/dev/null
fi

if [[ "$require_public" == true ]]; then
    public_length=$(curl --fail --silent --show-error --location \
        --proto '=https' --tlsv1.2 \
        --retry 5 --retry-all-errors --retry-delay 2 \
        --output /dev/null --write-out '%{size_download}' \
        "$actual_url")
    [[ "$public_length" == "$actual_length" ]] || fail "public release asset length does not match the appcast"
fi

echo "Sparkle appcast valid for $release_tag build $build_number."
