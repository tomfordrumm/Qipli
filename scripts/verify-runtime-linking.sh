#!/bin/bash

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail "usage: $0 /path/to/Qipli.app"
app_path="$1"
executable="$app_path/Contents/MacOS/Qipli"
sparkle_binary="$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
sparkle_dependency="@rpath/Sparkle.framework/Versions/B/Sparkle"
framework_runpath="@executable_path/../Frameworks"

[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"
[[ -x "$executable" ]] || fail "Qipli executable is missing: $executable"
[[ -x "$sparkle_binary" ]] || fail "embedded Sparkle binary is missing: $sparkle_binary"

architectures=$(lipo -archs "$executable")
[[ -n "$architectures" ]] || fail "Qipli executable has no architectures"

for architecture in $architectures; do
    dependencies=$(otool -arch "$architecture" -L "$executable")
    grep -Fq "$sparkle_dependency" <<<"$dependencies" \
        || fail "$architecture executable does not link the expected Sparkle framework"

    if ! otool -arch "$architecture" -l "$executable" | awk -v expected="$framework_runpath" '
        $1 == "cmd" && $2 == "LC_RPATH" {
            getline
            getline
            if ($1 == "path" && $2 == expected) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    '; then
        fail "$architecture executable cannot resolve embedded frameworks: missing LC_RPATH $framework_runpath"
    fi
done

echo "Runtime linking valid: embedded Sparkle resolves for $architectures."
