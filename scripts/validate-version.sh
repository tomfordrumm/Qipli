#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --marketing-version X.Y.Z --build-number N [--tag vX.Y.Z]" >&2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

marketing_version=""
build_number=""
tag=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --marketing-version)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            marketing_version="$2"
            shift 2
            ;;
        --build-number)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            build_number="$2"
            shift 2
            ;;
        --tag)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            tag="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -n "$marketing_version" ]] || fail "marketing version is required"
[[ -n "$build_number" ]] || fail "build number is required"

stable_version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$marketing_version" =~ $stable_version_pattern ]] \
    || fail "marketing version must use stable X.Y.Z format"

[[ "$build_number" =~ ^[1-9][0-9]*$ ]] \
    || fail "build number must be a positive integer without leading zeroes"

if [[ -n "$tag" ]]; then
    [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
        || fail "stable tag must use vX.Y.Z format"
    [[ "$tag" == "v$marketing_version" ]] \
        || fail "tag does not match marketing version"
fi

summary="Version contract valid: version=$marketing_version build=$build_number"
if [[ -n "$tag" ]]; then
    summary="$summary tag=$tag"
fi
echo "$summary"
