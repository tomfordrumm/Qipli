#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)

: "${QIPLI_DEVELOPMENT_TEAM:?Set QIPLI_DEVELOPMENT_TEAM to the Apple Developer Team ID}"
: "${QIPLI_DEVELOPER_ID_APPLICATION:?Set QIPLI_DEVELOPER_ID_APPLICATION to the full Developer ID Application certificate name}"
identity="$QIPLI_DEVELOPER_ID_APPLICATION"
team_id="$QIPLI_DEVELOPMENT_TEAM"
notary_timeout="${QIPLI_NOTARY_TIMEOUT:-30m}"
signing_keychain="${QIPLI_SIGNING_KEYCHAIN:-}"

[[ "$identity" == "Developer ID Application:"* ]] \
    || fail "release identity must start with 'Developer ID Application:'"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/qipli-release.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
archive_path="$work_dir/Qipli.xcarchive"

notary_arguments=()
if [[ -n "${QIPLI_NOTARY_PROFILE:-}" ]]; then
    notary_arguments=(--keychain-profile "$QIPLI_NOTARY_PROFILE")
elif [[ -n "${QIPLI_NOTARY_KEY_PATH:-}" ]] \
    && [[ -n "${QIPLI_NOTARY_KEY_ID:-}" ]] \
    && [[ -n "${QIPLI_NOTARY_ISSUER_ID:-}" ]]; then
    [[ -f "$QIPLI_NOTARY_KEY_PATH" ]] || fail "App Store Connect API key file does not exist"
    notary_arguments=(
        --key "$QIPLI_NOTARY_KEY_PATH"
        --key-id "$QIPLI_NOTARY_KEY_ID"
        --issuer "$QIPLI_NOTARY_ISSUER_ID"
    )
else
    fail "set a notarytool Keychain profile or complete App Store Connect API credentials"
fi

signing_flags="--timestamp"
if [[ -n "$signing_keychain" ]]; then
    [[ -f "$signing_keychain" ]] || fail "signing Keychain does not exist"
    signing_flags="$signing_flags --keychain $signing_keychain"
fi

cd "$repository_root"
xcodebuild \
    -project Qipli.xcodeproj \
    -scheme Qipli \
    -configuration Release \
    -archivePath "$archive_path" \
    clean archive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="$signing_flags"

app_path="$archive_path/Products/Applications/Qipli.app"
[[ -d "$app_path" ]] || fail "archive did not contain Qipli.app"

while IFS= read -r -d '' item; do
    for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
        if xattr "$item" 2>/dev/null | grep -Fxq "$attribute"; then
            xattr -d "$attribute" "$item"
        fi
    done
done < <(find "$app_path" -print0)

"$script_dir/verify-signed-app.sh" \
    --mode release \
    --team-id "$team_id" \
    --pre-notarization \
    "$app_path"

submission_path="$work_dir/Qipli-notarization.zip"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$app_path" "$submission_path"

notary_result="$work_dir/notary-result.plist"
xcrun notarytool submit "$submission_path" \
    "${notary_arguments[@]}" \
    --wait \
    --timeout "$notary_timeout" \
    --output-format plist > "$notary_result"

"$script_dir/validate-notary-result.sh" "$notary_result"

xcrun stapler staple "$app_path"
"$script_dir/verify-signed-app.sh" --mode release --team-id "$team_id" "$app_path"

version=$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")
mkdir -p "$repository_root/dist"
artifact_name="Qipli-$version.zip"
artifact_path="$repository_root/dist/$artifact_name"
[[ ! -e "$artifact_path" ]] || fail "output already exists: $artifact_path"
[[ ! -e "$artifact_path.sha256" ]] || fail "output already exists: $artifact_path.sha256"

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$app_path" "$artifact_path"

extracted_dir="$work_dir/extracted"
mkdir -p "$extracted_dir"
ditto -x -k "$artifact_path" "$extracted_dir"
"$script_dir/verify-signed-app.sh" --mode release --team-id "$team_id" "$extracted_dir/Qipli.app"

(
    cd "$repository_root/dist"
    shasum -a 256 "$artifact_name" > "$artifact_name.sha256"
)

echo "Created notarized release package: $artifact_path"
