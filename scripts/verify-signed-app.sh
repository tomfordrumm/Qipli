#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --mode local|release --team-id TEAM_ID [--pre-notarization] /path/to/Qipli.app" >&2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)

mode=""
team_id=""
pre_notarization=false
app_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            mode="$2"
            shift 2
            ;;
        --team-id)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            team_id="$2"
            shift 2
            ;;
        --pre-notarization)
            pre_notarization=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            fail "unknown option: $1"
            ;;
        *)
            [[ -z "$app_path" ]] || fail "only one app path is supported"
            app_path="$1"
            shift
            ;;
    esac
done

[[ "$mode" == "local" || "$mode" == "release" ]] || fail "--mode must be local or release"
[[ -n "$team_id" ]] || fail "--team-id is required"
[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"
[[ -x "$app_path/Contents/MacOS/Qipli" ]] || fail "Qipli executable is missing"

"$script_dir/verify-runtime-linking.sh" "$app_path"

signature_info=$(codesign --display --verbose=4 --requirements - "$app_path" 2>&1)

grep -Fq "Identifier=com.qipli.app" <<<"$signature_info" || fail "unexpected signing identifier"
grep -Fq "TeamIdentifier=$team_id" <<<"$signature_info" || fail "signature does not use Team ID $team_id"
grep -Eq 'flags=.*runtime' <<<"$signature_info" || fail "Hardened Runtime is not enabled"
grep -Fq "Signature=adhoc" <<<"$signature_info" && fail "ad-hoc signatures are not packageable"
grep -Eq '(# )?designated => .*identifier "com\.qipli\.app"' <<<"$signature_info" \
    || fail "designated requirement is not anchored to the bundle identifier"

if [[ "$mode" == "release" ]]; then
    grep -Fq "Authority=Developer ID Application:" <<<"$signature_info" \
        || fail "release is not signed with Developer ID Application"
    grep -Fq "Timestamp=" <<<"$signature_info" || fail "release signature has no secure timestamp"

    sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
    nested_release_code=(
        "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
        "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
        "$sparkle_framework/Versions/B/Autoupdate"
        "$sparkle_framework/Versions/B/Updater.app"
        "$sparkle_framework"
    )

    for nested_path in "${nested_release_code[@]}"; do
        [[ -e "$nested_path" ]] || fail "required Sparkle code is missing: $nested_path"
        nested_signature_info=$(/usr/bin/codesign --display --verbose=4 "$nested_path" 2>&1)
        grep -Fq "TeamIdentifier=$team_id" <<<"$nested_signature_info" \
            || fail "nested Sparkle code does not use Team ID $team_id: $nested_path"
        grep -Fq "Authority=Developer ID Application:" <<<"$nested_signature_info" \
            || fail "nested Sparkle code is not signed with Developer ID Application: $nested_path"
        grep -Fq "Timestamp=" <<<"$nested_signature_info" \
            || fail "nested Sparkle code has no secure timestamp: $nested_path"
        grep -Eq 'flags=.*runtime' <<<"$nested_signature_info" \
            || fail "nested Sparkle code does not use Hardened Runtime: $nested_path"
        grep -Fq "Signature=adhoc" <<<"$nested_signature_info" \
            && fail "nested Sparkle code is ad-hoc signed: $nested_path"
        /usr/bin/codesign --verify --strict --verbose=4 "$nested_path"
    done
else
    grep -Fq "Authority=Apple Development:" <<<"$signature_info" \
        || fail "local package is not signed with Apple Development"
fi

codesign --verify --deep --strict --verbose=4 "$app_path"

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/qipli-verify.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
entitlements_path="$temporary_dir/entitlements.plist"
codesign --display --entitlements "$entitlements_path" --xml "$app_path" 2>/dev/null

entitlement_is_true() {
    local key="$1"
    [[ -s "$entitlements_path" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements_path" 2>/dev/null || true)" == "true" ]]
}

for forbidden_entitlement in \
    com.apple.security.app-sandbox \
    com.apple.security.network.client \
    com.apple.security.network.server
do
    entitlement_is_true "$forbidden_entitlement" \
        && fail "forbidden entitlement is enabled: $forbidden_entitlement"
done

if [[ "$mode" == "release" ]] && entitlement_is_true com.apple.security.get-task-allow; then
    fail "release contains com.apple.security.get-task-allow"
fi

bundle_identifier=$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist")
minimum_system_version=$(plutil -extract LSMinimumSystemVersion raw -o - "$app_path/Contents/Info.plist")
[[ "$bundle_identifier" == "com.qipli.app" ]] || fail "unexpected bundle identifier: $bundle_identifier"
[[ "$minimum_system_version" == "14.0" ]] || fail "unexpected minimum macOS version: $minimum_system_version"

architectures=$(lipo -archs "$app_path/Contents/MacOS/Qipli")
[[ " $architectures " == *" arm64 "* ]] || fail "arm64 architecture is missing"
[[ " $architectures " == *" x86_64 "* ]] || fail "x86_64 architecture is missing"

forbidden_xattrs=$(xattr -lr "$app_path" 2>/dev/null \
    | grep -E 'com\.apple\.(FinderInfo|ResourceFork):' || true)
[[ -z "$forbidden_xattrs" ]] || fail "forbidden extended attributes found: $forbidden_xattrs"

if [[ "$mode" == "release" && "$pre_notarization" == false ]]; then
    xcrun stapler validate "$app_path"
    spctl --assess --type execute --verbose=4 "$app_path"
fi

echo "Verified $mode app: $app_path"
