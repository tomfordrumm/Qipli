#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/qipli-public-audit.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

cd "$repository_root"

current_paths="$work_dir/current-paths"
history_paths="$work_dir/history-paths"
current_secret_paths="$work_dir/current-secret-paths"
history_secret_paths="$work_dir/history-secret-paths"
history_dist_paths="$work_dir/history-dist-paths"

git ls-files -co --exclude-standard > "$current_paths"
git log --all --name-only --format= | sed '/^$/d' | sort -u > "$history_paths"

sensitive_path_pattern='(^|/)(\.env([^/]*)?|[^/]*\.(p12|p8|key|pem|mobileprovision))$'
clipboard_fixture_pattern='(^|/)(fixtures?|samples?|exports?)/[^/]*(clipboard|pasteboard|history)|(^|/)[^/]*(clipboard|pasteboard|history)[^/]*(fixture|sample|dump|export)'

path_failure=false
while IFS= read -r path; do
    if [[ "$path" =~ $sensitive_path_pattern ]] || [[ "$path" =~ $clipboard_fixture_pattern ]]; then
        echo "error: current tree contains prohibited public-readiness path: $path" >&2
        path_failure=true
    fi
done < "$current_paths"

while IFS= read -r path; do
    if [[ "$path" =~ $sensitive_path_pattern ]] || [[ "$path" =~ $clipboard_fixture_pattern ]]; then
        echo "error: Git history contains prohibited public-readiness path: $path" >&2
        path_failure=true
    fi
    if [[ "$path" == dist/* ]]; then
        echo "$path" >> "$history_dist_paths"
    fi
done < "$history_paths"

tracked_dist=$(git ls-files -- dist)
[[ -z "$tracked_dist" ]] || fail "dist contains tracked files"
git check-ignore -q dist/ || fail "dist/ is not ignored"

secret_pattern='-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}'

while IFS= read -r path; do
    [[ "$path" == "scripts/audit-public-readiness.sh" ]] && continue
    if grep -IlE -e "$secret_pattern" "$path" >/dev/null 2>&1; then
        echo "$path" >> "$current_secret_paths"
    fi
done < "$current_paths"

while IFS= read -r revision; do
    if git grep -I -l -E -e "$secret_pattern" "$revision" -- \
        . ':(exclude)scripts/audit-public-readiness.sh' \
        >> "$history_secret_paths" 2>/dev/null; then
        grep_status=0
    else
        grep_status=$?
    fi
    if [[ "$grep_status" -gt 1 ]]; then
        fail "unable to scan Git revision $revision"
    fi
    grep_status=0
done < <(git rev-list --all)

if [[ -s "$current_secret_paths" ]]; then
    sort -u "$current_secret_paths" | while IFS= read -r path; do
        echo "error: current tree contains a credential-shaped value in: $path" >&2
    done
    path_failure=true
fi

if [[ -s "$history_secret_paths" ]]; then
    sed -E 's/^[^:]+://' "$history_secret_paths" | sort -u | while IFS= read -r path; do
        echo "error: Git history contains a credential-shaped value in: $path" >&2
    done
    path_failure=true
fi

if [[ -s "$history_dist_paths" ]]; then
    history_dist_count=$(sort -u "$history_dist_paths" | wc -l | tr -d ' ')
    echo "warning: Git history contains $history_dist_count ignored release-output path(s); no current dist files are tracked." >&2
fi

[[ "$path_failure" == false ]] || fail "public-readiness audit found blocking paths or credential-shaped values"

current_file_count=$(wc -l < "$current_paths" | tr -d ' ')
revision_count=$(git rev-list --all --count)
echo "Public-readiness audit passed: $current_file_count current paths and $revision_count Git revisions checked; no payload values printed."
