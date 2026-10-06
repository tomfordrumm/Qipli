#!/bin/bash
set -euo pipefail

# Test utility only. Signing identity is deliberately explicit; no key material
# or release credentials are read by this script.
probe_source_dir="$(cd "$(dirname "$0")" && pwd)"
probe_repo_dir="$(cd "$probe_source_dir/../../.." && pwd)"
probe_output_dir="${S037_PROBE_OUTPUT_DIR:-/private/tmp/qipli-s037-probe-standalone}"
probe_app_dir="$probe_output_dir/Qipli Dev.app"
if [[ -z "${S037_PROBE_SIGNING_IDENTITY:-}" ]]; then
    echo 'Set S037_PROBE_SIGNING_IDENTITY to an available Apple Development identity.' >&2
    exit 2
fi
mkdir -p "$probe_app_dir/Contents/MacOS" "$probe_output_dir/module-cache"
/usr/bin/xcrun swiftc -D DEBUG -parse-as-library \
    -module-cache-path "$probe_output_dir/module-cache" \
    "$probe_source_dir/ProbeApp.swift" \
    "$probe_source_dir/S037PlatformProbe.swift" \
    "$probe_source_dir/S037FreshWordProbe.swift" \
    "$probe_source_dir/S037SelfAXRegression.swift" \
    "$probe_source_dir/S037ProductionAdapterProbe.swift" \
    "$probe_repo_dir/Sources/Qipli/Input/LayoutCorrectionAXAdapter.swift" \
    "$probe_repo_dir/Sources/Qipli/Input/SyntheticEventMarker.swift" \
    -o "$probe_app_dir/Contents/MacOS/Qipli"
cat > "$probe_app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.qipli.app.dev</string>
<key>CFBundleName</key><string>Qipli Dev</string>
<key>CFBundleExecutable</key><string>Qipli</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --options runtime --timestamp=none \
    --sign "$S037_PROBE_SIGNING_IDENTITY" "$probe_app_dir"
/usr/bin/codesign --verify --strict "$probe_app_dir"
echo "Built synthetic probe: $probe_app_dir"
echo 'Launch with --s037-fresh-word-manual-probe or an explicit mode documented in S037.'
