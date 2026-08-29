#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail "usage: $0 vX.Y.Z"
release_tag="$1"
script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${QIPLI_DEVELOPMENT_TEAM:?QIPLI_DEVELOPMENT_TEAM is required}"

"$script_dir/check-release-admission.sh" "$release_tag"

version_file="$repository_root/Config/Version.xcconfig"
version=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
build_number=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$version_file")
commit=$(git -C "$repository_root" rev-parse HEAD)
zip_name="Qipli-$version.zip"
zip_checksum_name="$zip_name.sha256"
dmg_name="Qipli-$version.dmg"
dmg_checksum_name="$dmg_name.sha256"
stable_dmg_name="Qipli.dmg"
zip_path="$repository_root/dist/$zip_name"
zip_checksum_path="$repository_root/dist/$zip_checksum_name"
dmg_path="$repository_root/dist/$dmg_name"
dmg_checksum_path="$repository_root/dist/$dmg_checksum_name"
[[ -f "$zip_path" ]] || fail "release artifact is missing: $zip_name"
[[ -f "$zip_checksum_path" ]] || fail "release checksum is missing: $zip_checksum_name"
[[ -f "$dmg_path" ]] || fail "release artifact is missing: $dmg_name"
[[ -f "$dmg_checksum_path" ]] || fail "release checksum is missing: $dmg_checksum_name"

(
    cd "$repository_root/dist"
    shasum -a 256 -c "$zip_checksum_name"
    shasum -a 256 -c "$dmg_checksum_name"
)

work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/qipli-publish.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
stable_dmg_path="$work_dir/$stable_dmg_name"
/usr/bin/ditto "$dmg_path" "$stable_dmg_path"
/usr/bin/cmp "$dmg_path" "$stable_dmg_path"

published_builds="$work_dir/published-builds"
gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
    --jq '.[] | select(.draft == false) | .body' \
    > "$published_builds"
highest_build=$(sed -nE 's/.*<!-- qipli-build: ([0-9]+) -->.*/\1/p' "$published_builds" \
    | sort -n \
    | tail -n 1)
if [[ -n "$highest_build" ]] && (( build_number <= highest_build )); then
    fail "build $build_number is not greater than published build $highest_build"
fi

release_state=""
if release_state=$(gh release view "$release_tag" --repo "$GITHUB_REPOSITORY" --json isDraft --jq '.isDraft' 2>/dev/null); then
    [[ "$release_state" == "true" ]] \
        || fail "release $release_tag is already published and immutable"
else
    gh api "repos/$GITHUB_REPOSITORY" >/dev/null
fi

generated_notes="$work_dir/generated-notes.md"
gh api --method POST "repos/$GITHUB_REPOSITORY/releases/generate-notes" \
    -f tag_name="$release_tag" \
    -f target_commitish="$commit" \
    --jq '.body' \
    > "$generated_notes"

release_notes="$work_dir/release-notes.md"
sed "s/^# Qipli release notes/# Qipli $version/" \
    "$repository_root/docs/release-notes-template.md" > "$release_notes"
printf '\nBuild: `%s`\n\n<!-- qipli-build: %s -->\n\n' "$build_number" "$build_number" >> "$release_notes"
printf '%s\n' "$(<"$generated_notes")" >> "$release_notes"

if [[ -z "$release_state" ]]; then
    gh release create "$release_tag" \
        --repo "$GITHUB_REPOSITORY" \
        --draft \
        --verify-tag \
        --target "$commit" \
        --title "Qipli $version" \
        --notes-file "$release_notes"
else
    gh release edit "$release_tag" \
        --repo "$GITHUB_REPOSITORY" \
        --title "Qipli $version" \
        --notes-file "$release_notes"
fi

gh release upload "$release_tag" \
    "$zip_path" \
    "$zip_checksum_path" \
    "$dmg_path" \
    "$dmg_checksum_path" \
    "$stable_dmg_path" \
    --repo "$GITHUB_REPOSITORY" \
    --clobber

candidate_dir="$work_dir/candidate"
mkdir -p "$candidate_dir"
gh release download "$release_tag" \
    --repo "$GITHUB_REPOSITORY" \
    --dir "$candidate_dir" \
    --pattern "$zip_name" \
    --pattern "$zip_checksum_name" \
    --pattern "$dmg_name" \
    --pattern "$dmg_checksum_name" \
    --pattern "$stable_dmg_name" \
    --clobber
(
    cd "$candidate_dir"
    shasum -a 256 -c "$zip_checksum_name"
    shasum -a 256 -c "$dmg_checksum_name"
)
/usr/bin/cmp "$candidate_dir/$dmg_name" "$candidate_dir/$stable_dmg_name"
candidate_app_dir="$work_dir/candidate-app"
mkdir -p "$candidate_app_dir"
ditto -x -k "$candidate_dir/$zip_name" "$candidate_app_dir"
"$script_dir/verify-signed-app.sh" \
    --mode release \
    --team-id "$QIPLI_DEVELOPMENT_TEAM" \
    "$candidate_app_dir/Qipli.app"
"$script_dir/verify-dmg.sh" \
    --mode release \
    --team-id "$QIPLI_DEVELOPMENT_TEAM" \
    "$candidate_dir/$dmg_name"

gh release edit "$release_tag" \
    --repo "$GITHUB_REPOSITORY" \
    --draft=false \
    --latest

public_dir="$work_dir/public"
mkdir -p "$public_dir"
public_base_url="https://github.com/$GITHUB_REPOSITORY/releases/download/$release_tag"
for public_asset in \
    "$zip_name" \
    "$zip_checksum_name" \
    "$dmg_name" \
    "$dmg_checksum_name" \
    "$stable_dmg_name"
do
    curl --fail --location --proto '=https' --tlsv1.2 \
        --retry 5 --retry-all-errors --retry-delay 2 \
        --output "$public_dir/$public_asset" \
        "$public_base_url/$public_asset"
done
(
    cd "$public_dir"
    shasum -a 256 -c "$zip_checksum_name"
    shasum -a 256 -c "$dmg_checksum_name"
)
/usr/bin/cmp "$public_dir/$dmg_name" "$public_dir/$stable_dmg_name"
public_app_dir="$work_dir/public-app"
mkdir -p "$public_app_dir"
ditto -x -k "$public_dir/$zip_name" "$public_app_dir"
"$script_dir/verify-signed-app.sh" \
    --mode release \
    --team-id "$QIPLI_DEVELOPMENT_TEAM" \
    "$public_app_dir/Qipli.app"
"$script_dir/verify-dmg.sh" \
    --mode release \
    --team-id "$QIPLI_DEVELOPMENT_TEAM" \
    "$public_dir/$dmg_name"

latest_dmg_path="$work_dir/latest-$stable_dmg_name"
latest_dmg_url="https://github.com/$GITHUB_REPOSITORY/releases/latest/download/$stable_dmg_name"
curl --fail --location --proto '=https' --tlsv1.2 \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --output "$latest_dmg_path" \
    "$latest_dmg_url"
/usr/bin/cmp "$public_dir/$dmg_name" "$latest_dmg_path"

echo "Published and reverified: https://github.com/$GITHUB_REPOSITORY/releases/tag/$release_tag"
echo "Direct installer: $latest_dmg_url"
