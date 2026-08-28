#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
workflow="$repository_root/.github/workflows/release.yml"
hosted_packager="$repository_root/scripts/package-hosted-release.sh"
publisher="$repository_root/scripts/publish-github-release.sh"

[[ -f "$workflow" ]] || fail "missing .github/workflows/release.yml"
[[ -f "$hosted_packager" ]] || fail "missing hosted release packager"
[[ -f "$publisher" ]] || fail "missing GitHub release publisher"

grep -Eq '^  push:$' "$workflow" || fail "release workflow must have a push trigger"
grep -Fq "      - 'v*.*.*'" "$workflow" || fail "release workflow must be limited to version tags"
grep -Eq '^  workflow_dispatch:$' "$workflow" || fail "release workflow must support reviewed recovery runs"
grep -Eq '^  contents: write$' "$workflow" || fail "release workflow must declare contents write"
grep -Eq '^    environment: release$' "$workflow" || fail "release job must use the protected release environment"
grep -Eq '^    runs-on: macos-26$' "$workflow" || fail "release workflow must use macos-26"
grep -Fq 'scripts/check-release-admission.sh' "$workflow" || fail "release admission check is missing"
grep -Fq 'scripts/package-hosted-release.sh' "$workflow" || fail "hosted signing boundary is missing"
grep -Fq 'scripts/publish-github-release.sh' "$workflow" || fail "draft verification and publication boundary is missing"

if grep -Eq 'pull_request|pull_request_target|branches:' "$workflow"; then
    fail "release workflow must not run for pull requests or branch pushes"
fi

action_references=$(sed -nE 's/^[[:space:]]*uses:[[:space:]]*([^[:space:]#]+).*/\1/p' "$workflow")
while IFS= read -r action_reference; do
    [[ "$action_reference" == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" ]] \
        || fail "unapproved or unpinned release action: $action_reference"
done <<< "$action_references"

grep -Fq 'trap cleanup EXIT INT TERM' "$hosted_packager" \
    || fail "hosted credential cleanup trap is missing"
grep -Fq '/usr/bin/security delete-keychain' "$hosted_packager" \
    || fail "ephemeral Keychain cleanup is missing"
grep -Fq '/usr/bin/security list-keychains -d user -s' "$hosted_packager" \
    || fail "ephemeral Keychain search-list setup is missing"
grep -Fq 'original_user_keychains' "$hosted_packager" \
    || fail "original Keychain search-list restoration is missing"
grep -Fq '/usr/bin/security find-identity -v -p codesigning' "$hosted_packager" \
    || fail "imported Developer ID identity preflight is missing"
grep -Fq 'release $release_tag is already published and immutable' "$publisher" \
    || fail "published release immutability check is missing"
grep -Fq 'gh release download' "$publisher" \
    || fail "authenticated draft asset download is missing"
grep -Fq 'public_base_url=' "$publisher" \
    || fail "public unauthenticated download verification is missing"

echo "Release contract valid: protected tag workflow, ephemeral credentials, draft verification, immutable publication."
