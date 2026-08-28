#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
version_config="$repository_root/Config/Version.xcconfig"
info_plist="$repository_root/Sources/Qipli/Resources/Info.plist"
tag=""
built_plist=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            [[ $# -ge 2 ]] || fail "--tag requires a value"
            tag="$2"
            shift 2
            ;;
        --built-plist)
            [[ $# -ge 2 ]] || fail "--built-plist requires a path"
            built_plist="$2"
            shift 2
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

read_config_value() {
    local key="$1"
    awk -F '=' -v expected_key="$key" '
        {
            key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == expected_key) {
                value = $2
                sub(/[[:space:]]*\/\/.*/, "", value)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                exit
            }
        }
    ' "$version_config"
}

read_build_setting() {
    local key="$1"
    awk -F ' = ' -v expected_key="$key" '
        {
            key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == expected_key) {
                print $2
                exit
            }
        }
    '
}

[[ -f "$version_config" ]] || fail "missing Config/Version.xcconfig"
marketing_version=$(read_config_value MARKETING_VERSION)
build_number=$(read_config_value CURRENT_PROJECT_VERSION)

validator_arguments=(
    --marketing-version "$marketing_version"
    --build-number "$build_number"
)
if [[ -n "$tag" ]]; then
    validator_arguments+=(--tag "$tag")
fi
"$script_dir/validate-version.sh" "${validator_arguments[@]}"

source_marketing=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info_plist")
source_build=$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info_plist")
[[ "$source_marketing" == '$(MARKETING_VERSION)' ]] \
    || fail "source Info.plist must use MARKETING_VERSION"
[[ "$source_build" == '$(CURRENT_PROJECT_VERSION)' ]] \
    || fail "source Info.plist must use CURRENT_PROJECT_VERSION"

for configuration in Debug Release; do
    settings=$(xcodebuild \
        -project "$repository_root/Qipli.xcodeproj" \
        -target Qipli \
        -configuration "$configuration" \
        -showBuildSettings)
    configured_marketing=$(printf '%s\n' "$settings" | read_build_setting MARKETING_VERSION)
    configured_build=$(printf '%s\n' "$settings" | read_build_setting CURRENT_PROJECT_VERSION)
    [[ "$configured_marketing" == "$marketing_version" ]] \
        || fail "$configuration MARKETING_VERSION does not match Version.xcconfig"
    [[ "$configured_build" == "$build_number" ]] \
        || fail "$configuration CURRENT_PROJECT_VERSION does not match Version.xcconfig"
done

if [[ -n "$built_plist" ]]; then
    [[ -f "$built_plist" ]] || fail "built Info.plist not found: $built_plist"
    built_marketing=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$built_plist")
    built_number=$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$built_plist")
    [[ "$built_marketing" == "$marketing_version" ]] \
        || fail "built CFBundleShortVersionString does not match Version.xcconfig"
    [[ "$built_number" == "$build_number" ]] \
        || fail "built CFBundleVersion does not match Version.xcconfig"
    echo "Project version settings agree in Debug, Release, source plist and built artifact."
else
    echo "Project version settings agree in Debug, Release and source plist."
fi
