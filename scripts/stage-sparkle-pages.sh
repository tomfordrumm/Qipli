#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 3 ]] || fail "usage: $0 vX.Y.Z appcast.xml output-directory"
release_tag="$1"
appcast_path="$2"
output_directory="$3"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' \
    "$repository_root/Config/Version.xcconfig")
archive_path="$repository_root/dist/Qipli-$version.zip"

release_state=$(gh release view "$release_tag" \
    --repo "$GITHUB_REPOSITORY" \
    --json isDraft \
    --jq '.isDraft')
[[ "$release_state" == "false" ]] || fail "release $release_tag must be public before its appcast is staged"

"$script_dir/verify-sparkle-appcast.sh" \
    --tag "$release_tag" \
    --archive "$archive_path" \
    --appcast "$appcast_path" \
    --require-public

[[ ! -e "$output_directory" ]] || fail "Pages output already exists: $output_directory"
mkdir -p "$output_directory"
cp "$appcast_path" "$output_directory/appcast.xml"
touch "$output_directory/.nojekyll"

echo "Staged verified Sparkle Pages artifact for $release_tag."
