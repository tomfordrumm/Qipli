#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail "usage: $0 /path/to/notary-result.plist"
result_path="$1"
[[ -f "$result_path" ]] || fail "notary result not found: $result_path"

status=$(plutil -extract status raw -o - "$result_path" 2>/dev/null || true)
submission_id=$(plutil -extract id raw -o - "$result_path" 2>/dev/null || true)
[[ "$status" == "Accepted" ]] \
    || fail "notarization was not accepted (status: ${status:-unknown}, submission: ${submission_id:-unknown})"

echo "Notarization accepted (submission: ${submission_id:-unknown})."
