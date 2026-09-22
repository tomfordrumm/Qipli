## Requirements

- macOS 14 or newer
- Accessibility permission for global shortcuts and paste commands

## Install

Download `Qipli.dmg`, open it, drag `Qipli.app` to Applications, eject the disk
image, and launch Qipli. The versioned DMG and matching `.sha256` file are also
available for checksum verification. The DMG and app are signed with Developer ID
and notarized by Apple; the ZIP remains the immutable Sparkle update artifact.

## Using Qipli

Onboarding explains the local clipboard history and can be skipped or reopened
from Settings. Settings contains Accessibility status, configurable Qipli
shortcuts, an opt-in Launch at Login control, manual update checks, and an
off-by-default periodic update check.

## Privacy

Qipli keeps 30 days of clipboard history on the current Mac. Favorites remain until
you remove them. History includes copied
text, standard RTF/HTML formatting, URLs, filenames, file references, and managed
images. It has no account, telemetry, cloud sync, or automatic secret filtering. Copied passwords or API
keys can enter local history. Qipli uses the network only for a manual update
check or periodic update checks after explicit opt-in; update requests do not
include clipboard, URLs, filenames, paths, images, History, search, or preview
values.

Source code and license: https://github.com/tomfordrumm/Qipli

## Changes

- Collect and paste rich text and images in Paste Stack, with compact previews and a panel that expands on interaction.
- Open any of the five most recent History items directly from the menu bar and paste it into the app you were using.
- Use Command-X and Command-V to request native file moves in Finder, with a compact status panel. Finder handles conflicts and the move itself.
- Protect active Paste Stack payloads from automatic History expiry.
- Keep the selected History item during background refreshes and reject outdated search results.
- Simplify storage, paste handling, and panel code for easier maintenance.

Existing History and favorites are preserved; this release does not change the database schema.
