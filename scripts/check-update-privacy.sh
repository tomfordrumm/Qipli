#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
update_source="$repository_root/Sources/Qipli/Updates"
info_plist="$repository_root/Sources/Qipli/Resources/Info.plist"

[[ -d "$update_source" ]] || fail "missing isolated Updates module"
[[ -f "$info_plist" ]] || fail "missing app Info.plist"

for prohibited in HistoryService HistoryStore StackSession Pasteboard NSPasteboard searchQuery preview; do
    if rg -n --fixed-strings "$prohibited" "$update_source" >/dev/null; then
        fail "Updates module must not access product payload symbol: $prohibited"
    fi
done

if rg -n 'print\(|NSLog\(|os_log|Logger\(' "$update_source" >/dev/null; then
    fail "Updates module must not add application logging"
fi

grep -Fq '<key>SUPublicEDKey</key>' "$info_plist" || fail "missing public Sparkle key"
if rg -n 'QIPLI_SPARKLE_PRIVATE_KEY|PRIVATE KEY' Sources Tests Config Package.swift Qipli.xcodeproj >/dev/null; then
    fail "private Sparkle key reference crossed into the product or tests"
fi

echo "Update privacy boundary valid: public metadata only, no product payload access or application logging."
