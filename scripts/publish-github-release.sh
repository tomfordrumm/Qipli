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
artifact_name="Qipli-$version.zip"
checksum_name="$artifact_name.sha256"
artifact_path="$repository_root/dist/$artifact_name"
checksum_path="$repository_root/dist/$checksum_name"
[[ -f "$artifact_path" ]] || fail "release artifact is missing: $artifact_name"
[[ -f "$checksum_path" ]] || fail "release checksum is missing: $checksum_name"

(
    cd "$repository_root/dist"
    shasum -a 256 -c "$checksum_name"
)

work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/qipli-publish.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

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
    "$artifact_path" \
    "$checksum_path" \
    --repo "$GITHUB_REPOSITORY" \
    --clobber

candidate_dir="$work_dir/candidate"
mkdir -p "$candidate_dir"
gh release download "$release_tag" \
    --repo "$GITHUB_REPOSITORY" \
    --dir "$candidate_dir" \
    --pattern "$artifact_name" \
    --pattern "$checksum_name" \
    --clobber
(
    cd "$candidate_dir"
    shasum -a 256 -c "$checksum_name"
)
candidate_app_dir="$work_dir/candidate-app"
mkdir -p "$candidate_app_dir"
ditto -x -k "$candidate_dir/$artifact_name" "$candidate_app_dir"
"$script_dir/verify-signed-app.sh" \
    --mode release \
    --team-id "$QIPLI_DEVELOPMENT_TEAM" \
    "$candidate_app_dir/Qipli.app"

gh release edit "$release_tag" \
    --repo "$GITHUB_REPOSITORY" \
    --draft=false \
    --latest

public_dir="$work_dir/public"
mkdir -p "$public_dir"
public_base_url="https://github.com/$GITHUB_REPOSITORY/releases/download/$release_tag"
curl --fail --location --proto '=https' --tlsv1.2 \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --output "$public_dir/$artifact_name" \
    "$public_base_url/$artifact_name"
curl --fail --location --proto '=https' --tlsv1.2 \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --output "$public_dir/$checksum_name" \
    "$public_base_url/$checksum_name"
(
    cd "$public_dir"
    shasum -a 256 -c "$checksum_name"
)
public_app_dir="$work_dir/public-app"
mkdir -p "$public_app_dir"
ditto -x -k "$public_dir/$artifact_name" "$public_app_dir"
"$script_dir/verify-signed-app.sh" \
    --mode release \
    --team-id "$QIPLI_DEVELOPMENT_TEAM" \
    "$public_app_dir/Qipli.app"

echo "Published and reverified: https://github.com/$GITHUB_REPOSITORY/releases/tag/$release_tag"
