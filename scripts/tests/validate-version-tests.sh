#!/bin/bash

set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
validator="$script_dir/../validate-version.sh"
passed=0

expect_success() {
    local name="$1"
    shift
    if "$validator" "$@" >/dev/null 2>&1; then
        passed=$((passed + 1))
    else
        echo "FAIL: $name should succeed" >&2
        exit 1
    fi
}

expect_failure() {
    local name="$1"
    shift
    if "$validator" "$@" >/dev/null 2>&1; then
        echo "FAIL: $name should fail" >&2
        exit 1
    else
        passed=$((passed + 1))
    fi
}

expect_success "valid stable version" \
    --marketing-version 1.0.0 --build-number 1 --tag v1.0.0
expect_failure "tag mismatch" \
    --marketing-version 1.0.0 --build-number 1 --tag v1.0.1
expect_failure "zero build" \
    --marketing-version 1.0.0 --build-number 0
expect_failure "non-numeric build" \
    --marketing-version 1.0.0 --build-number build-1
expect_failure "prerelease marketing version" \
    --marketing-version 1.0.0-beta.1 --build-number 1
expect_failure "prerelease tag" \
    --marketing-version 1.0.0 --build-number 1 --tag v1.0.0-beta.1
expect_failure "noncanonical stable version" \
    --marketing-version 1.0 --build-number 1
expect_failure "leading-zero build" \
    --marketing-version 1.0.0 --build-number 01

echo "Version validator tests passed: $passed"
