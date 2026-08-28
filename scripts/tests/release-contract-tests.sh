#!/bin/bash

set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/../.." && pwd)
passed=0

expect_success() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        passed=$((passed + 1))
    else
        echo "FAIL: $name should succeed" >&2
        exit 1
    fi
}

expect_failure() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: $name should fail" >&2
        exit 1
    else
        passed=$((passed + 1))
    fi
}

"$repository_root/scripts/check-release-contract.sh" >/dev/null
passed=$((passed + 1))

validator="$repository_root/scripts/validate-hosted-release-environment.sh"
expect_failure "missing hosted secrets" env -i PATH="$PATH" "$validator"

certificate_base64=$(printf 'certificate' | /usr/bin/base64)
notary_key_base64=$(printf 'notary-key' | /usr/bin/base64)
valid_environment=(
    QIPLI_DEVELOPMENT_TEAM=ABCDEFGHIJ
    'QIPLI_DEVELOPER_ID_APPLICATION=Developer ID Application: Test (ABCDEFGHIJ)'
    QIPLI_DEVELOPER_ID_P12_BASE64="$certificate_base64"
    QIPLI_DEVELOPER_ID_P12_PASSWORD=test-password
    QIPLI_NOTARY_KEY_P8_BASE64="$notary_key_base64"
    QIPLI_NOTARY_KEY_ID=K123456789
    QIPLI_NOTARY_ISSUER_ID=12345678-1234-1234-1234-123456789abc
)
expect_success "complete hosted environment" env "${valid_environment[@]}" "$validator"
expect_failure "invalid certificate encoding" env \
    "${valid_environment[@]}" \
    QIPLI_DEVELOPER_ID_P12_BASE64='not base64!' \
    "$validator"

notary_validator="$repository_root/scripts/validate-notary-result.sh"
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/qipli-release-tests.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
accepted_plist="$fixture_dir/accepted.plist"
rejected_plist="$fixture_dir/rejected.plist"
plutil -create xml1 "$accepted_plist"
plutil -insert status -string Accepted "$accepted_plist"
plutil -insert id -string accepted-submission "$accepted_plist"
plutil -create xml1 "$rejected_plist"
plutil -insert status -string Invalid "$rejected_plist"
plutil -insert id -string rejected-submission "$rejected_plist"
expect_success "accepted notarization" "$notary_validator" "$accepted_plist"
expect_failure "rejected notarization" "$notary_validator" "$rejected_plist"

sparkle_app="$fixture_dir/Qipli.app"
sparkle_framework="$sparkle_app/Contents/Frameworks/Sparkle.framework"
mkdir -p \
    "$sparkle_framework/Versions/B/XPCServices/Installer.xpc" \
    "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc" \
    "$sparkle_framework/Versions/B/Updater.app"
touch "$sparkle_framework/Versions/B/Autoupdate"
codesign_log="$fixture_dir/codesign.log"
QIPLI_CODESIGN_BIN="$repository_root/scripts/tests/fixtures/fake-codesign.sh" \
QIPLI_CODESIGN_LOG="$codesign_log" \
    "$repository_root/scripts/resign-sparkle-for-release.sh" \
    --identity 'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$sparkle_app" >/dev/null
expected_codesign_log="$fixture_dir/expected-codesign.log"
printf '%s|false|true|true|%s\n%s|true|true|true|%s\n%s|false|true|true|%s\n%s|false|true|true|%s\n%s|false|true|true|%s\n%s|false|true|true|%s\n' \
    "$sparkle_framework/Versions/B/XPCServices/Installer.xpc" \
    'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc" \
    'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$sparkle_framework/Versions/B/Autoupdate" \
    'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$sparkle_framework/Versions/B/Updater.app" \
    'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$sparkle_framework" \
    'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$sparkle_app" \
    'Developer ID Application: Test (ABCDEFGHIJ)' > "$expected_codesign_log"
expect_success "Sparkle inside-out signing order" cmp "$expected_codesign_log" "$codesign_log"
expect_failure "missing Sparkle helper" \
    env QIPLI_CODESIGN_BIN="$repository_root/scripts/tests/fixtures/fake-codesign.sh" \
    QIPLI_CODESIGN_LOG="$codesign_log" \
    "$repository_root/scripts/resign-sparkle-for-release.sh" \
    --identity 'Developer ID Application: Test (ABCDEFGHIJ)' \
    "$fixture_dir/missing.app"

admission_repository="$fixture_dir/admission"
mkdir -p "$admission_repository/Config"
git -C "$admission_repository" init -q
git -C "$admission_repository" config user.name Qipli-Test
git -C "$admission_repository" config user.email qipli-test@example.invalid
printf 'MARKETING_VERSION = 1.0.0\nCURRENT_PROJECT_VERSION = 1\n' \
    > "$admission_repository/Config/Version.xcconfig"
git -C "$admission_repository" add Config/Version.xcconfig
git -C "$admission_repository" commit -q -m initial
git -C "$admission_repository" branch -M main
git -C "$admission_repository" update-ref refs/remotes/origin/main HEAD
git -C "$admission_repository" tag v1.0.0
admission="$repository_root/scripts/check-release-admission.sh"
expect_success "tag on main" "$admission" --repository "$admission_repository" v1.0.0
expect_failure "tag version mismatch" "$admission" --repository "$admission_repository" v1.0.1
printf 'off-main\n' > "$admission_repository/off-main.txt"
git -C "$admission_repository" add off-main.txt
git -C "$admission_repository" commit -q -m off-main
git -C "$admission_repository" tag v1.0.1
expect_failure "tag outside origin main" "$admission" --repository "$admission_repository" v1.0.1

echo "Release contract tests passed: $passed"
