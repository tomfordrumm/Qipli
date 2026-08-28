#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

: "${QIPLI_SPARKLE_PRIVATE_KEY:?QIPLI_SPARKLE_PRIVATE_KEY is required}"
script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
info_plist="$repository_root/Sources/Qipli/Resources/Info.plist"

expected_public_key=$(plutil -extract SUPublicEDKey raw -o - "$info_plist")
actual_public_key=$(printf '%s' "$QIPLI_SPARKLE_PRIVATE_KEY" \
    | xcrun swift "$script_dir/derive-sparkle-public-key.swift")
[[ "$actual_public_key" == "$expected_public_key" ]] \
    || fail "protected Sparkle key does not match SUPublicEDKey"

echo "Protected Sparkle key matches the application's public key."
