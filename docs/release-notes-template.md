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

- Expand optional local diagnostics for keyboard-layout correction. Journals now record the specific Accessibility call and attribute, numeric system error, response type, requested range, expected and observed lengths, focus and selection checks, call timing, and remaining deadline.
- Follow each correction through admission, mapping, selection, native or Unicode paste, postcondition checks, keyboard-layout switching, and clipboard restoration. A fixed browser category and input-owner state help identify the affected path.
- Record a terminal outcome with the concrete failure. Numbered events and explicit overflow counts make incomplete diagnostic trails visible.

Logging remains off by default. If it was enabled in 1.0.14, the setting is preserved after updating. Otherwise enable it in Settings → General → Diagnostics before reproducing an incident. Show Logs opens the local journal folder; Clear Logs removes the journals.

Diagnostics contain structural checks, numeric ranges and fixed categories. They exclude field and clipboard contents, keystrokes, raw application/window/layout identities, URLs and file paths. Journals stay on this Mac, rotate at 10 MiB, and expire after seven days while Qipli is running or on its next launch. There is no automatic upload.

Manual layout correction requires a compatible editable field and supported static keyboard layouts. Existing History, favorites, shortcuts, Accessibility permissions and diagnostic preferences are preserved; this release does not change the database schema.
