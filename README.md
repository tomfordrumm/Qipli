# Qipli

Qipli is a native macOS clipboard history and sequential paste utility. It keeps
30 days of text history on the current Mac and adds a Paste Stack for collecting
several values before pasting them one by one with the normal `Command-V` shortcut.

## Requirements

- macOS 14 or newer
- Accessibility permission for global shortcuts and synthetic paste commands

## Install

1. Open the latest GitHub Release.
2. Download `Qipli-X.Y.Z.zip` and its `.sha256` file.
3. Optionally verify the download with `shasum -a 256 -c Qipli-X.Y.Z.zip.sha256`.
4. Unzip Qipli and move `Qipli.app` to `/Applications`.
5. Launch Qipli and follow the optional onboarding. macOS may ask you to allow
   Qipli under System Settings > Privacy & Security > Accessibility.

Public release archives are signed with Developer ID, notarized by Apple, and
checked with Gatekeeper before publication. Do not use a build from an untrusted
fork or an unsigned CI run as an installed release.

## Use

- `Command-Shift-V` opens clipboard history.
- `Command-Shift-C` starts or continues a Paste Stack and copies from the active app.
- `Command-V` pastes the next pending Stack item while a Stack is active.
- `Command-Shift-Z` reactivates the last successfully dispatched Stack item.

You can change the three Qipli shortcuts in Settings. The normal `Command-V` and
`Escape` behavior are not configurable.

## Privacy

Qipli stores clipboard history locally on the current Mac for 30 days. It has no
account, telemetry, cloud sync, or automatic crash reporting. Qipli does not
automatically recognize passwords, API keys, or other sensitive text, so copied
secrets can enter local history. You can delete one history item or clear all
Qipli history at any time.

The current version does not make runtime network requests. Secure update checks
will be added separately and will remain off by default until the user opts in.

## Build and test

Open `Qipli.xcodeproj` in Xcode, or run:

```sh
swift test
xcodebuild \
  -project Qipli.xcodeproj \
  -scheme Qipli \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Release signing credentials never belong in the repository. Pull requests and
pushes to `main` run unsigned tests and builds only.

## Security

Please report vulnerabilities through the private process described in
[`SECURITY.md`](SECURITY.md). Do not include real clipboard contents, signing
keys, or other secrets in a public issue.

## License

Qipli is available under the [MIT License](LICENSE).
