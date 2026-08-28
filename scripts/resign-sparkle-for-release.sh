#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --identity 'Developer ID Application: ...' [--keychain /path/to/keychain] /path/to/Qipli.app" >&2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

identity=""
keychain=""
app_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            identity="$2"
            shift 2
            ;;
        --keychain)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            keychain="$2"
            shift 2
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

[[ "$identity" == "Developer ID Application:"* ]] \
    || fail "--identity must be a Developer ID Application certificate name"
[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"
if [[ -n "$keychain" ]]; then
    [[ -f "$keychain" ]] || fail "signing Keychain does not exist: $keychain"
fi

# The override exists only for the command-order fixture. The release verifier
# deliberately invokes /usr/bin/codesign directly after this script completes.
codesign_bin="${QIPLI_CODESIGN_BIN:-/usr/bin/codesign}"
[[ -x "$codesign_bin" ]] || fail "codesign executable not found: $codesign_bin"

framework="$app_path/Contents/Frameworks/Sparkle.framework"
installer_xpc="$framework/Versions/B/XPCServices/Installer.xpc"
downloader_xpc="$framework/Versions/B/XPCServices/Downloader.xpc"
autoupdate="$framework/Versions/B/Autoupdate"
updater_app="$framework/Versions/B/Updater.app"

for required_path in \
    "$installer_xpc" \
    "$downloader_xpc" \
    "$autoupdate" \
    "$updater_app" \
    "$framework"
do
    [[ -e "$required_path" ]] || fail "required Sparkle code is missing: $required_path"
done

signing_arguments=(
    --force
    --verbose
    --sign "$identity"
    --timestamp
    --options runtime
)
if [[ -n "$keychain" ]]; then
    signing_arguments+=(--keychain "$keychain")
fi

resign_target() {
    "$codesign_bin" "${signing_arguments[@]}" "$@"
}

# Sparkle 2.6+ requires this inside-out order for non-standard archive exports.
resign_target "$installer_xpc"
resign_target --preserve-metadata=entitlements "$downloader_xpc"
resign_target "$autoupdate"
resign_target "$updater_app"
resign_target "$framework"

# Updating the embedded framework invalidates the outer bundle seal.
resign_target --preserve-metadata=identifier,entitlements,requirements "$app_path"

echo "Re-signed Sparkle framework and Qipli.app for Developer ID distribution."
