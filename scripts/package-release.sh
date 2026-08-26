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
: "${QIPLI_NOTARY_PROFILE:?Set QIPLI_NOTARY_PROFILE to a notarytool Keychain profile name}"

identity="$QIPLI_DEVELOPER_ID_APPLICATION"
team_id="$QIPLI_DEVELOPMENT_TEAM"
notary_profile="$QIPLI_NOTARY_PROFILE"
notary_timeout="${QIPLI_NOTARY_TIMEOUT:-30m}"

[[ "$identity" == "Developer ID Application:"* ]] \
    || fail "release identity must start with 'Developer ID Application:'"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/qipli-release.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
archive_path="$work_dir/Qipli.xcarchive"

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
    OTHER_CODE_SIGN_FLAGS=--timestamp

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
    --keychain-profile "$notary_profile" \
    --wait \
    --timeout "$notary_timeout" \
    --output-format plist > "$notary_result"

notary_status=$(plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)
submission_id=$(plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)
[[ "$notary_status" == "Accepted" ]] \
    || fail "notarization was not accepted (status: ${notary_status:-unknown}, submission: ${submission_id:-unknown})"

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
