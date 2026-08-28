#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
: "${RUNNER_TEMP:?RUNNER_TEMP is required on the hosted runner}"

"$script_dir/validate-hosted-release-environment.sh"

umask 077
credential_dir=$(mktemp -d "$RUNNER_TEMP/qipli-hosted-release.XXXXXX")
keychain_path="$credential_dir/qipli-signing.keychain-db"
certificate_path="$credential_dir/developer-id.p12"
notary_key_path="$credential_dir/AuthKey_${QIPLI_NOTARY_KEY_ID}.p8"
keychain_password=$(/usr/bin/openssl rand -hex 32)

cleanup() {
    /usr/bin/security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
    /bin/rm -f "$certificate_path" "$notary_key_path"
    /bin/rm -rf "$credential_dir"
}
trap cleanup EXIT INT TERM

printf '%s' "$QIPLI_DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$certificate_path"
printf '%s' "$QIPLI_NOTARY_KEY_P8_BASE64" | /usr/bin/base64 -D > "$notary_key_path"

/usr/bin/security create-keychain -p "$keychain_password" "$keychain_path"
/usr/bin/security set-keychain-settings -lut 21600 "$keychain_path"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain_path"
/usr/bin/security import "$certificate_path" \
    -k "$keychain_path" \
    -P "$QIPLI_DEVELOPER_ID_P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
/usr/bin/security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$keychain_path" >/dev/null

QIPLI_SIGNING_KEYCHAIN="$keychain_path" \
QIPLI_NOTARY_KEY_PATH="$notary_key_path" \
QIPLI_NOTARY_KEY_ID="$QIPLI_NOTARY_KEY_ID" \
QIPLI_NOTARY_ISSUER_ID="$QIPLI_NOTARY_ISSUER_ID" \
"$script_dir/package-release.sh"
