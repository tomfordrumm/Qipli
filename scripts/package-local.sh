#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)

: "${QIPLI_DEVELOPMENT_TEAM:?Set QIPLI_DEVELOPMENT_TEAM to the Apple Developer Team ID}"
: "${QIPLI_APPLE_DEVELOPMENT_IDENTITY:?Set QIPLI_APPLE_DEVELOPMENT_IDENTITY to the full Apple Development certificate name}"

identity="$QIPLI_APPLE_DEVELOPMENT_IDENTITY"
team_id="$QIPLI_DEVELOPMENT_TEAM"
[[ "$identity" == "Apple Development:"* ]] || fail "local identity must start with 'Apple Development:'"

available_identities=$(security find-identity -v -p codesigning)
grep -Fq "\"$identity\"" <<<"$available_identities" \
    || fail "Apple Development identity is not available in the keychain: $identity"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/qipli-local.XXXXXX")
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
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

app_path="$archive_path/Products/Applications/Qipli.app"
[[ -d "$app_path" ]] || fail "archive did not contain Qipli.app"

while IFS= read -r -d '' item; do
    for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
        if xattr "$item" 2>/dev/null | grep -Fxq "$attribute"; then
            xattr -d "$attribute" "$item"
        fi
    done
done < <(find "$app_path" -print0)

"$script_dir/verify-signed-app.sh" --mode local --team-id "$team_id" "$app_path"

version=$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")
mkdir -p "$repository_root/dist"
artifact_name="Qipli-$version-local.zip"
artifact_path="$repository_root/dist/$artifact_name"
[[ ! -e "$artifact_path" ]] || fail "output already exists: $artifact_path"
[[ ! -e "$artifact_path.sha256" ]] || fail "output already exists: $artifact_path.sha256"

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$app_path" "$artifact_path"

extracted_dir="$work_dir/extracted"
mkdir -p "$extracted_dir"
ditto -x -k "$artifact_path" "$extracted_dir"
"$script_dir/verify-signed-app.sh" --mode local --team-id "$team_id" "$extracted_dir/Qipli.app"

(
    cd "$repository_root/dist"
    shasum -a 256 "$artifact_name" > "$artifact_name.sha256"
)

echo "Created local package: $artifact_path"
echo "This package is for the signing team's local testing, not public distribution."
