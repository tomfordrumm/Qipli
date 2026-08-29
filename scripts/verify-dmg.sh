#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --mode layout|release [--team-id TEAM_ID] [--pre-notarization] /path/to/Qipli.dmg" >&2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
mode=""
team_id=""
pre_notarization=false
dmg_path=""

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
            [[ -z "$dmg_path" ]] || fail "only one DMG path is supported"
            dmg_path="$1"
            shift
            ;;
    esac
done

[[ "$mode" == "layout" || "$mode" == "release" ]] || fail "--mode must be layout or release"
[[ -f "$dmg_path" ]] || fail "DMG not found: $dmg_path"
if [[ "$mode" == "release" ]]; then
    [[ -n "$team_id" ]] || fail "--team-id is required in release mode"

    signature_info=$(/usr/bin/codesign --display --verbose=4 "$dmg_path" 2>&1)
    grep -Fq "Authority=Developer ID Application:" <<<"$signature_info" \
        || fail "DMG is not signed with Developer ID Application"
    grep -Fq "TeamIdentifier=$team_id" <<<"$signature_info" \
        || fail "DMG signature does not use Team ID $team_id"
    grep -Fq "Timestamp=" <<<"$signature_info" \
        || fail "DMG signature has no secure timestamp"
    grep -Fq "Signature=adhoc" <<<"$signature_info" \
        && fail "DMG is ad-hoc signed"
    /usr/bin/codesign --verify --strict --verbose=4 "$dmg_path"

    if [[ "$pre_notarization" == false ]]; then
        /usr/bin/xcrun stapler validate "$dmg_path"
        /usr/sbin/spctl --assess \
            --type open \
            --context context:primary-signature \
            --verbose=4 \
            "$dmg_path"
    fi
fi

hdiutil_bin="${QIPLI_HDIUTIL_BIN:-/usr/bin/hdiutil}"
[[ -x "$hdiutil_bin" ]] || fail "hdiutil is unavailable"

temporary_root="${TMPDIR:-/tmp}"
work_dir=$(mktemp -d "${temporary_root%/}/qipli-verify-dmg.XXXXXX")
work_dir=$(cd "$work_dir" && pwd -P)
mount_dir="$work_dir/mount"
mounted_device=""

cleanup() {
    if [[ -n "$mounted_device" ]]; then
        "$hdiutil_bin" detach "$mounted_device" -quiet >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$mount_dir"
attach_output=$("$hdiutil_bin" attach \
    -readonly \
    -noverify \
    -noautoopen \
    -nobrowse \
    -mountpoint "$mount_dir" \
    "$dmg_path")
mounted_device=$(printf '%s\n' "$attach_output" \
    | /usr/bin/awk -v mount="$mount_dir" 'index($0, mount) { print $1; exit }')
[[ -n "$mounted_device" ]] || fail "could not resolve the mounted DMG device"

[[ -d "$mount_dir/Qipli.app" ]] || fail "DMG does not contain Qipli.app"
[[ -L "$mount_dir/Applications" ]] || fail "DMG Applications item is not a symlink"
[[ "$(/usr/bin/readlink "$mount_dir/Applications")" == "/Applications" ]] \
    || fail "DMG Applications symlink has an unexpected target"
[[ -s "$mount_dir/.DS_Store" ]] || fail "DMG Finder layout is missing"
background="$mount_dir/.background/install-background.png"
[[ -s "$background" ]] || fail "DMG background is missing"

background_width=$(/usr/bin/sips -g pixelWidth "$background" \
    | /usr/bin/awk '/pixelWidth:/ { print $2 }')
background_height=$(/usr/bin/sips -g pixelHeight "$background" \
    | /usr/bin/awk '/pixelHeight:/ { print $2 }')
background_dpi=$(/usr/bin/sips -g dpiWidth "$background" \
    | /usr/bin/awk '/dpiWidth:/ { print $2 }')
[[ "$background_width" == "1320" && "$background_height" == "840" ]] \
    || fail "DMG background must be 1320x840 pixels"
[[ "$background_dpi" == "144.000" ]] \
    || fail "DMG background must use 144 dpi Retina metadata"

while IFS= read -r item; do
    case "$(basename "$item")" in
        .background|.DS_Store|.metadata_never_index|Applications|Qipli.app)
            ;;
        *)
            fail "unexpected top-level DMG item: $(basename "$item")"
            ;;
    esac
done < <(/usr/bin/find "$mount_dir" -mindepth 1 -maxdepth 1 -print)

if [[ "$mode" == "release" ]]; then
    "$script_dir/verify-signed-app.sh" \
        --mode release \
        --team-id "$team_id" \
        "$mount_dir/Qipli.app"
fi

"$hdiutil_bin" detach "$mounted_device" -quiet
mounted_device=""

echo "Verified $mode DMG: $dmg_path"
