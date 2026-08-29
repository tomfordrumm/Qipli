#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --app /path/to/Qipli.app --output /path/to/Qipli-X.Y.Z.dmg" >&2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
background_path="$repository_root/release-assets/dmg/install-background.png"
layout_script="$repository_root/release-assets/dmg/configure-window.applescript"
app_path=""
output_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            app_path="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            output_path="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"
[[ -n "$output_path" ]] || fail "--output is required"
[[ "$output_path" == *.dmg ]] || fail "output must use the .dmg extension"
[[ ! -e "$output_path" ]] || fail "output already exists: $output_path"
[[ -f "$background_path" ]] || fail "DMG background is missing"
[[ -f "$layout_script" ]] || fail "DMG Finder layout script is missing"

hdiutil_bin="${QIPLI_HDIUTIL_BIN:-/usr/bin/hdiutil}"
osascript_bin="${QIPLI_OSASCRIPT_BIN:-/usr/bin/osascript}"
[[ -x "$hdiutil_bin" ]] || fail "hdiutil is unavailable"
[[ -x "$osascript_bin" ]] || fail "osascript is unavailable"

mkdir -p "$(dirname "$output_path")"
temporary_root="${TMPDIR:-/tmp}"
work_dir=$(mktemp -d "${temporary_root%/}/qipli-dmg.XXXXXX")
work_dir=$(cd "$work_dir" && pwd -P)
staging_dir="$work_dir/staging"
mount_dir="$work_dir/mount"
read_write_dmg="$work_dir/Qipli-read-write.dmg"
converted_base="$work_dir/Qipli-compressed"
mounted_device=""

cleanup() {
    if [[ -n "$mounted_device" ]]; then
        "$hdiutil_bin" detach "$mounted_device" -quiet >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$staging_dir/.background" "$mount_dir"
/usr/bin/ditto "$app_path" "$staging_dir/Qipli.app"
/usr/bin/ditto "$background_path" "$staging_dir/.background/install-background.png"
/bin/ln -s /Applications "$staging_dir/Applications"
/usr/bin/touch "$staging_dir/.metadata_never_index"

"$hdiutil_bin" create \
    -quiet \
    -fs APFS \
    -format UDRW \
    -volname Qipli \
    -srcfolder "$staging_dir" \
    "$read_write_dmg"

attach_output=$("$hdiutil_bin" attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -nobrowse \
    -mountpoint "$mount_dir" \
    "$read_write_dmg")
mounted_device=$(printf '%s\n' "$attach_output" \
    | /usr/bin/awk -v mount="$mount_dir" 'index($0, mount) { print $1; exit }')
[[ -n "$mounted_device" ]] || fail "could not resolve the mounted DMG device"

"$osascript_bin" "$layout_script" "$mount_dir"
/bin/rm -rf \
    "$mount_dir/.fseventsd" \
    "$mount_dir/.Spotlight-V100" \
    "$mount_dir/.Trashes"
/bin/sync
/bin/sleep 2
"$hdiutil_bin" detach "$mounted_device" -quiet
mounted_device=""

"$hdiutil_bin" convert \
    "$read_write_dmg" \
    -quiet \
    -format ULFO \
    -o "$converted_base"
[[ -f "$converted_base.dmg" ]] || fail "hdiutil did not create the compressed DMG"
/bin/mv "$converted_base.dmg" "$output_path"

echo "Created DMG layout: $output_path"
