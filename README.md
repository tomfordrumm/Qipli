<div align="center">
  <img src="release-assets/app-icon/QipliIcon-master.png" width="128" alt="Qipli app icon">
  <h1>Qipli</h1>
  <p><strong>A native clipboard history and sequential paste utility for macOS.</strong></p>
  <p>
    <a href="https://github.com/tomfordrumm/Qipli/releases/latest/download/Qipli.dmg">Download</a> ·
    <a href="https://qipli.yhub.net">Website</a> ·
    <a href="https://github.com/tomfordrumm/Qipli/releases">Releases</a> ·
    <a href="SECURITY.md">Security</a>
  </p>
  <p>
    <a href="https://github.com/tomfordrumm/Qipli/actions/workflows/ci.yml"><img src="https://github.com/tomfordrumm/Qipli/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/tomfordrumm/Qipli" alt="MIT license"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-111827" alt="macOS 14 or newer">
  </p>
</div>

Qipli keeps clipboard history on the current Mac, with automatic cleanup after
30 days and favorites you can keep longer. It supports plain and formatted text,
URLs, inline images, and references to local files or videos. Its Paste Stack
collects text and images and pastes them one by one with the normal `Command-V`
shortcut.

## Why Qipli

- **Local by default.** No account, telemetry, cloud sync, or automatic crash
  reporting.
- **Keyboard-first.** Open History, collect a Paste Stack, and paste through the
  active app without leaving the keyboard.
- **Predictable.** The normal `Command-V` and `Escape` behavior stays unchanged
  outside an active Paste Stack or Finder Cut session.
- **Native.** Qipli uses macOS panels, permissions, settings, and release
  conventions instead of adding a second UI layer.

## Features

### History

Open a searchable shelf of recent copies, select an exact entry, and paste it back
into the app you were using. Text retains its formatting by default; use
`Shift-Enter` to paste it as plain text. Individual entries and the complete
Qipli history can be deleted. The menu bar also offers the five most recent
History items for immediate paste; these actions are unavailable while a Paste
Stack is active.

Star an entry to keep it beyond automatic History expiry. Use the star in the
History header to show only favorites and search within them.

### Paste Stack

Collect plain text, formatted text, and images from the active app, review their
order, and paste them one at a time. The compact panel shows previews and expands
for review and reordering. Choose whether to paste from top to bottom or bottom
to top. A stack is a temporary session; its active payloads are protected from
automatic History expiry until the session ends. File and video references are
available in History, but cannot be collected into a Paste Stack.

### Finder Cut

In Finder, use `Command-X` on selected files and `Command-V` in a destination
folder to request Finder's native move. A compact panel shows the prepared
selection. Finder handles file operations, conflicts, and permissions; the panel
does not confirm that a move completed.

Finder Cut supports regular local files. Folders, iCloud items, and files on
network volumes are not supported.

### Settings

History, Paste Stack, and Reactivate Previous shortcuts can be changed in
Settings and restored to their defaults. Enable Launch at Login if you want Qipli
to open when you sign in to your Mac.

### Updates you control

Use `Check for Updates…` from the menu bar or Settings for a manual check.
Periodic checks are off by default and start only after you enable them.

## Requirements

- macOS 14 or newer
- Accessibility permission for global shortcuts and synthetic paste commands

## Install

1. Download [`Qipli.dmg`](https://github.com/tomfordrumm/Qipli/releases/latest/download/Qipli.dmg).
2. Open the disk image and drag `Qipli.app` to Applications.
3. Eject the disk image, launch Qipli, and follow the optional onboarding.
4. If macOS asks for it, allow Qipli under System Settings > Privacy & Security
   > Accessibility.

The versioned DMG and its `.sha256` file remain available on the release page for
manual verification. Public DMGs and app bundles are signed with Developer ID,
notarized by Apple, and checked with Gatekeeper before publication. The ZIP is the
immutable Sparkle update artifact. Do not install builds from an untrusted fork or
an unsigned CI run.

## Shortcuts

| Action | Default shortcut |
| --- | --- |
| Open History | `Command-Shift-V` |
| Paste the selected History item | `Enter` in History |
| Paste selected History text without formatting | `Shift-Enter` in History |
| Delete the selected History item | `Shift-Backspace` with History search focused |
| Start or collect a Paste Stack item | `Command-Shift-C` |
| Paste the next Stack item | `Command-V` while a Stack is active |
| Reactivate the last dispatched Stack item | `Command-Shift-Z` |
| Cancel the active Stack | `Escape` |
| Prepare selected files for a move | `Command-X` in Finder |
| Request the prepared file move | `Command-V` in the destination Finder folder |

The three Qipli shortcuts can be changed in Settings and restored to their
defaults. The regular `Command-V` and `Escape` commands are not configurable.

## Privacy

Qipli stores copied plain and formatted text, URLs, filenames, file references,
and managed image data locally on the current Mac. Ordinary History entries
expire after 30 days without capture or reuse. Favorites are excluded from
automatic expiry, and active Paste Stack payloads stay protected until the
session ends. You can still delete individual entries or clear all Qipli history,
including favorites and entries used by an active Stack.

File and video entries reference the original files; Qipli does not keep backup
copies of their contents. Inline images and text formatting are stored by Qipli.

It has no account, telemetry, cloud sync, or automatic crash reporting. Qipli does
not automatically recognize passwords, API keys, or other sensitive content, so
copied secrets can enter local history.

The only runtime network path is Sparkle: a manual check, or periodic checks after
explicit opt-in, reads Qipli's public GitHub Pages appcast and a selected GitHub
Release archive. Clipboard text, URLs, filenames, paths, images, History, searches,
previews, and local identifiers are not added to update requests.

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

For interactive testing, run the `Qipli` scheme in Xcode with normal Apple
Development signing. Debug builds are named `Qipli Dev.app` and use
`com.qipli.app.dev`. Add this app once under System Settings → Privacy & Security
→ Accessibility; keep the installed Qipli permission enabled. The unsigned
command above is only a build check, not a permission-testing build.

Qipli Dev has separate preferences and no Sparkle updates, but intentionally
shares the installed app's History database and managed assets. Quit one version
before running the other. Deleting History or testing a database migration in Dev
affects the same data used by the installed app.

Release signing credentials never belong in the repository. Pull requests and
pushes to `main` run unsigned tests and builds only.

## Project docs

- [Product contract](docs/PRODUCT.md)
- [Technical contract and architecture](docs/TECHNICAL.md)
- [Release preparation and publication](docs/RELEASING.md)
- [Security policy](SECURITY.md)

## Security

Please report vulnerabilities through the private process described in
[`SECURITY.md`](SECURITY.md). Do not include real clipboard contents, signing
keys, or other secrets in a public issue.

## License

Qipli is available under the [MIT License](LICENSE).
