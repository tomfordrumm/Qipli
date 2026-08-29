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
sparkle_resigner="$repository_root/scripts/resign-sparkle-for-release.sh"
release_packager="$repository_root/scripts/package-release.sh"
signed_app_verifier="$repository_root/scripts/verify-signed-app.sh"
runtime_link_verifier="$repository_root/scripts/verify-runtime-linking.sh"
dmg_builder="$repository_root/scripts/create-dmg.sh"
dmg_verifier="$repository_root/scripts/verify-dmg.sh"
dmg_background="$repository_root/release-assets/dmg/install-background.png"
dmg_layout="$repository_root/release-assets/dmg/configure-window.applescript"

[[ -f "$workflow" ]] || fail "missing .github/workflows/release.yml"
[[ -f "$hosted_packager" ]] || fail "missing hosted release packager"
[[ -f "$publisher" ]] || fail "missing GitHub release publisher"
[[ -f "$appcast_generator" ]] || fail "missing Sparkle appcast generator"
[[ -f "$pages_stager" ]] || fail "missing Sparkle Pages stager"
[[ -f "$sparkle_key_validator" ]] || fail "missing Sparkle key validator"
[[ -f "$sparkle_resigner" ]] || fail "missing Sparkle release resigner"
[[ -x "$runtime_link_verifier" ]] || fail "missing executable runtime linking verifier"
[[ -x "$dmg_builder" ]] || fail "missing executable DMG builder"
[[ -x "$dmg_verifier" ]] || fail "missing executable DMG verifier"
[[ -s "$dmg_background" ]] || fail "missing DMG background"
[[ -s "$dmg_layout" ]] || fail "missing DMG Finder layout"

dmg_background_width=$(/usr/bin/sips -g pixelWidth "$dmg_background" \
    | /usr/bin/awk '/pixelWidth:/ { print $2 }')
dmg_background_height=$(/usr/bin/sips -g pixelHeight "$dmg_background" \
    | /usr/bin/awk '/pixelHeight:/ { print $2 }')
dmg_background_dpi=$(/usr/bin/sips -g dpiWidth "$dmg_background" \
    | /usr/bin/awk '/dpiWidth:/ { print $2 }')
[[ "$dmg_background_width" == "1320" && "$dmg_background_height" == "840" ]] \
    || fail "DMG background must be 1320x840 pixels"
[[ "$dmg_background_dpi" == "144.000" ]] \
    || fail "DMG background must use 144 dpi Retina metadata"

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
grep -Fq 'scripts/verify-runtime-linking.sh' "$workflow" || fail "unsigned release gate must verify runtime linking"
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
grep -Fq 'stable_dmg_name="Qipli.dmg"' "$publisher" \
    || fail "stable direct-download DMG asset is missing"
grep -Fq 'releases/latest/download/$stable_dmg_name' "$publisher" \
    || fail "latest DMG direct-download verification is missing"
grep -Fq 'QIPLI_SPARKLE_PRIVATE_KEY' "$appcast_generator" \
    || fail "appcast generator must require the protected EdDSA key"
grep -Fq -- '--ed-key-file -' "$appcast_generator" \
    || fail "appcast private key must be passed over standard input"
grep -Fq -- '--require-public' "$pages_stager" \
    || fail "Pages stager must verify the public immutable asset"
grep -Fq 'resign-sparkle-for-release.sh' "$release_packager" \
    || fail "release packaging must re-sign nested Sparkle code"
grep -Fq 'create-dmg.sh' "$release_packager" \
    || fail "release packaging must create a DMG installer"
grep -Fq 'verify-dmg.sh' "$release_packager" \
    || fail "release packaging must verify the DMG installer"
grep -Fq 'xcrun notarytool submit "$dmg_path"' "$release_packager" \
    || fail "release packaging must notarize the final DMG"
grep -Fq 'xcrun stapler staple "$dmg_path"' "$release_packager" \
    || fail "release packaging must staple the final DMG"
grep -Fq 'archive_name="Qipli-$version.zip"' "$appcast_generator" \
    || fail "Sparkle updates must remain on the versioned ZIP artifact"
resign_step_line=$(grep -n 'resign-sparkle-for-release.sh' "$release_packager" | cut -d: -f1)
pre_notary_verify_line=$(grep -n '"$script_dir/verify-signed-app.sh" \\' "$release_packager" | head -n 1 | cut -d: -f1)
(( resign_step_line < pre_notary_verify_line )) \
    || fail "nested Sparkle signing must run before pre-notarization verification"

dmg_create_line=$(grep -n 'create-dmg.sh' "$release_packager" | cut -d: -f1)
dmg_codesign_line=$(grep -n '/usr/bin/codesign ' "$release_packager" | cut -d: -f1)
dmg_notary_line=$(grep -n 'xcrun notarytool submit "$dmg_path"' "$release_packager" | cut -d: -f1)
dmg_staple_line=$(grep -n 'xcrun stapler staple "$dmg_path"' "$release_packager" | cut -d: -f1)
dmg_final_verify_line=$(grep -n 'verify-dmg.sh" --mode release' "$release_packager" | tail -n 1 | cut -d: -f1)
(( dmg_create_line < dmg_codesign_line \
    && dmg_codesign_line < dmg_notary_line \
    && dmg_notary_line < dmg_staple_line \
    && dmg_staple_line < dmg_final_verify_line )) \
    || fail "DMG must be created, signed, notarized, stapled, and verified in order"

installer_line=$(grep -n 'resign_target "$installer_xpc"' "$sparkle_resigner" | cut -d: -f1)
downloader_line=$(grep -n 'resign_target --preserve-metadata=entitlements "$downloader_xpc"' "$sparkle_resigner" | cut -d: -f1)
autoupdate_line=$(grep -n 'resign_target "$autoupdate"' "$sparkle_resigner" | cut -d: -f1)
updater_line=$(grep -n 'resign_target "$updater_app"' "$sparkle_resigner" | cut -d: -f1)
framework_line=$(grep -n 'resign_target "$framework"' "$sparkle_resigner" | cut -d: -f1)
outer_app_line=$(grep -n 'resign_target --preserve-metadata=identifier,entitlements,requirements "$app_path"' "$sparkle_resigner" | cut -d: -f1)
(( installer_line < downloader_line \
    && downloader_line < autoupdate_line \
    && autoupdate_line < updater_line \
    && updater_line < framework_line \
    && framework_line < outer_app_line )) \
    || fail "Sparkle code must be signed inside-out before the outer app"
if grep -Fq -- '--deep' "$sparkle_resigner"; then
    fail "Sparkle release signing must not use --deep"
fi

for nested_component in Installer.xpc Downloader.xpc Autoupdate Updater.app Sparkle.framework; do
    grep -Fq "$nested_component" "$signed_app_verifier" \
        || fail "release verifier must inspect nested Sparkle component: $nested_component"
done
grep -Fq 'verify-runtime-linking.sh' "$signed_app_verifier" \
    || fail "signed app verifier must reject missing embedded-framework runpaths"

release_line=$(grep -n 'scripts/publish-github-release.sh' "$workflow" | head -n 1 | cut -d: -f1)
appcast_line=$(grep -n 'scripts/stage-sparkle-pages.sh' "$workflow" | head -n 1 | cut -d: -f1)
(( appcast_line > release_line )) || fail "appcast must be published after the GitHub Release"

echo "Release contract valid: protected tag workflow, notarized DMG and ZIP, immutable release, signed appcast published last."
