#!/bin/bash
set -euo pipefail
probe_source_dir="$(cd "$(dirname "$0")" && pwd)"
probe_repo_dir="$(cd "$probe_source_dir/../../.." && pwd)"
probe_output_dir=/private/tmp/qipli-s037-final-cut
: "${S037_PROBE_SIGNING_IDENTITY:?Set a local Apple Development identity}"
probe_app_dir="$probe_output_dir/Qipli Dev.app"
mkdir -p "$probe_app_dir/Contents/MacOS" "$probe_output_dir/module-cache"
xcrun swiftc -D DEBUG ${S037_FINALCUT_SWIFT_FLAGS:-} -parse-as-library -module-cache-path "$probe_output_dir/module-cache" \
  "$probe_source_dir/S037FinalCutProbe.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/LayoutCorrectionAXAdapter.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/CorrectionDiagnostics.swift" \
  "$probe_repo_dir/Sources/Qipli/Settings/LocalDiagnostics.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/LayoutCorrectionCoordinator.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/NativeLayoutCorrectionTransport.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/LayoutCorrectionPreferences.swift" \
  "$probe_repo_dir/Sources/Qipli/Settings/ShortcutPreferences.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/CorrectionFreshWordMonitor.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/LayoutCorrectionModels.swift" \
  "$probe_repo_dir/Sources/Qipli/Input/LayoutCorrectionSourceCatalog.swift" \
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
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp=none --sign "$S037_PROBE_SIGNING_IDENTITY" "$probe_app_dir"
codesign --verify --strict "$probe_app_dir"
echo 'Built Final Cut synthetic search integration probe. Requires prefilled ghbdtn in effects search; never use in a document field.'
