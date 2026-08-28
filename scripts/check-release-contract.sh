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
appcast_generator="$repository_root/scripts/generate-sparkle-appcast.sh"
pages_stager="$repository_root/scripts/stage-sparkle-pages.sh"
sparkle_key_validator="$repository_root/scripts/validate-sparkle-release-key.sh"

[[ -f "$workflow" ]] || fail "missing .github/workflows/release.yml"
[[ -f "$hosted_packager" ]] || fail "missing hosted release packager"
[[ -f "$publisher" ]] || fail "missing GitHub release publisher"
[[ -f "$appcast_generator" ]] || fail "missing Sparkle appcast generator"
[[ -f "$pages_stager" ]] || fail "missing Sparkle Pages stager"
[[ -f "$sparkle_key_validator" ]] || fail "missing Sparkle key validator"

grep -Eq '^  push:$' "$workflow" || fail "release workflow must have a push trigger"
grep -Fq "      - 'v*.*.*'" "$workflow" || fail "release workflow must be limited to version tags"
grep -Eq '^  workflow_dispatch:$' "$workflow" || fail "release workflow must support reviewed recovery runs"
grep -Eq '^  contents: write$' "$workflow" || fail "release workflow must declare contents write"
grep -Eq '^    environment: release$' "$workflow" || fail "release job must use the protected release environment"
grep -Eq '^    runs-on: macos-26$' "$workflow" || fail "release workflow must use macos-26"
grep -Fq 'scripts/check-release-admission.sh' "$workflow" || fail "release admission check is missing"
grep -Fq 'scripts/package-hosted-release.sh' "$workflow" || fail "hosted signing boundary is missing"
grep -Fq 'scripts/publish-github-release.sh' "$workflow" || fail "draft verification and publication boundary is missing"
grep -Fq 'scripts/generate-sparkle-appcast.sh' "$workflow" || fail "signed appcast preparation is missing"
grep -Fq 'scripts/stage-sparkle-pages.sh' "$workflow" || fail "verified Pages staging is missing"
grep -Fq 'scripts/validate-sparkle-release-key.sh' "$workflow" || fail "Sparkle key preflight is missing"
grep -Fq 'actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9' "$workflow" \
    || fail "pinned Pages upload action is missing"
grep -Fq 'actions/deploy-pages@cd2ce8fcbc39b97be8ca5fce6e763baed58fa128' "$workflow" \
    || fail "pinned Pages deployment action is missing"

if grep -Eq 'pull_request|pull_request_target|branches:' "$workflow"; then
    fail "release workflow must not run for pull requests or branch pushes"
fi

action_references=$(sed -nE 's/^[[:space:]]*uses:[[:space:]]*([^[:space:]#]+).*/\1/p' "$workflow")
while IFS= read -r action_reference; do
    case "$action_reference" in
        actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1|\
        actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9|\
        actions/deploy-pages@cd2ce8fcbc39b97be8ca5fce6e763baed58fa128)
            ;;
        *)
            fail "unapproved or unpinned release action: $action_reference"
            ;;
    esac
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
grep -Fq 'QIPLI_SPARKLE_PRIVATE_KEY' "$appcast_generator" \
    || fail "appcast generator must require the protected EdDSA key"
grep -Fq -- '--ed-key-file -' "$appcast_generator" \
    || fail "appcast private key must be passed over standard input"
grep -Fq -- '--require-public' "$pages_stager" \
    || fail "Pages stager must verify the public immutable asset"

release_line=$(grep -n 'scripts/publish-github-release.sh' "$workflow" | head -n 1 | cut -d: -f1)
appcast_line=$(grep -n 'scripts/stage-sparkle-pages.sh' "$workflow" | head -n 1 | cut -d: -f1)
(( appcast_line > release_line )) || fail "appcast must be published after the GitHub Release"

echo "Release contract valid: protected tag workflow, ephemeral credentials, immutable release, signed appcast published last."
