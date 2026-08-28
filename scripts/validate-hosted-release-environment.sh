#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

required_names=(
    QIPLI_DEVELOPMENT_TEAM
    QIPLI_DEVELOPER_ID_APPLICATION
    QIPLI_DEVELOPER_ID_P12_BASE64
    QIPLI_DEVELOPER_ID_P12_PASSWORD
    QIPLI_NOTARY_KEY_P8_BASE64
    QIPLI_NOTARY_KEY_ID
    QIPLI_NOTARY_ISSUER_ID
)

for required_name in "${required_names[@]}"; do
    [[ -n "${!required_name:-}" ]] || fail "missing hosted release value: $required_name"
done

[[ "$QIPLI_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] \
    || fail "QIPLI_DEVELOPMENT_TEAM must be a 10-character Team ID"
[[ "$QIPLI_DEVELOPER_ID_APPLICATION" == "Developer ID Application:"*" ($QIPLI_DEVELOPMENT_TEAM)" ]] \
    || fail "Developer ID identity must be the full certificate name for the configured Team ID"
[[ "$QIPLI_NOTARY_KEY_ID" =~ ^[A-Z0-9]{10,}$ ]] \
    || fail "QIPLI_NOTARY_KEY_ID must be an alphanumeric key ID with at least 10 characters"
[[ "$QIPLI_NOTARY_ISSUER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] \
    || fail "QIPLI_NOTARY_ISSUER_ID must be an issuer UUID"

validate_base64() {
    local label="$1"
    local value="$2"
    local compact_value="${value//$'\n'/}"
    compact_value="${compact_value//$'\r'/}"
    [[ "$compact_value" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] \
        || fail "$label secret is not valid base64"
    (( ${#compact_value} % 4 == 0 )) \
        || fail "$label secret is not valid base64"
    printf '%s' "$compact_value" | /usr/bin/base64 -D >/dev/null 2>&1 \
        || fail "$label secret is not valid base64"
}

validate_base64 "Developer ID certificate" "$QIPLI_DEVELOPER_ID_P12_BASE64"
validate_base64 "App Store Connect key" "$QIPLI_NOTARY_KEY_P8_BASE64"

echo "Hosted release environment is complete."
