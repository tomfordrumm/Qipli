#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    echo "Usage: $0 [--repository PATH] vX.Y.Z" >&2
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)

if [[ "${1:-}" == "--repository" ]]; then
    [[ $# -ge 3 ]] || { usage; exit 2; }
    repository_root="$2"
    shift 2
fi

[[ $# -eq 1 ]] || { usage; exit 2; }
release_tag="$1"
version_file="$repository_root/Config/Version.xcconfig"
[[ -f "$version_file" ]] || fail "missing Config/Version.xcconfig"

marketing_version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
build_number=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
[[ -n "$marketing_version" ]] || fail "MARKETING_VERSION is missing"
[[ -n "$build_number" ]] || fail "CURRENT_PROJECT_VERSION is missing"

"$script_dir/validate-version.sh" \
    --marketing-version "$marketing_version" \
    --build-number "$build_number" \
    --tag "$release_tag"

head_commit=$(git -C "$repository_root" rev-parse HEAD)
tag_commit=$(git -C "$repository_root" rev-parse "$release_tag^{}" 2>/dev/null) \
    || fail "release tag does not exist: $release_tag"
[[ "$head_commit" == "$tag_commit" ]] || fail "checked-out commit does not match $release_tag"

main_commit=$(git -C "$repository_root" rev-parse refs/remotes/origin/main 2>/dev/null) \
    || fail "origin/main is unavailable"
git -C "$repository_root" merge-base --is-ancestor "$tag_commit" "$main_commit" \
    || fail "release tag must point to a commit contained in origin/main"

echo "Release admission valid: $release_tag, version $marketing_version, build $build_number."
