#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
workflow="$repository_root/.github/workflows/ci.yml"

[[ -f "$workflow" ]] || fail "missing .github/workflows/ci.yml"
grep -Eq '^  pull_request:$' "$workflow" || fail "CI must run on pull_request"
grep -Eq '^  push:$' "$workflow" || fail "CI must run on push"
grep -Eq '^      - main$' "$workflow" || fail "CI push trigger must be limited to main"
grep -Eq '^permissions:$' "$workflow" || fail "CI must declare top-level permissions"
grep -Eq '^  contents: read$' "$workflow" || fail "CI must grant only contents: read"
grep -Eq '^concurrency:$' "$workflow" || fail "CI must define concurrency"
grep -Eq '^  cancel-in-progress: true$' "$workflow" || fail "CI must cancel stale runs for the same ref"
grep -Eq '^    runs-on: macos-26$' "$workflow" || fail "CI must use the reviewed macos-26 runner"
grep -Fq 'scripts/tests/release-contract-tests.sh' "$workflow" \
    || fail "CI must validate the release packaging contract without secrets"
grep -Fq 'scripts/verify-runtime-linking.sh' "$workflow" \
    || fail "CI must verify embedded framework runtime linking"

if grep -Eq 'pull_request_target|secrets\.|permissions: write|contents: write|package-release\.sh|notarytool|codesign|security import|gh release|upload-artifact' "$workflow"; then
    fail "CI contains a release, secret, write-permission or artifact-upload path"
fi

action_references=$(sed -nE 's/^[[:space:]]*uses:[[:space:]]*([^[:space:]#]+).*/\1/p' "$workflow")
[[ -n "$action_references" ]] || fail "CI must check out the repository through an explicit action"
while IFS= read -r action_reference; do
    [[ "$action_reference" == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" ]] \
        || fail "unapproved or unpinned action: $action_reference"
done <<< "$action_references"

echo "CI contract valid: read-only permissions, pinned official action, no release secrets or artifacts."
