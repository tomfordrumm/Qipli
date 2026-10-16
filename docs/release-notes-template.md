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

- Rework manual keyboard-layout correction for better compatibility with editors such as Final Cut Pro. Selected text now uses native Copy/Paste; the last typed word uses a short-lived buffer of physical keys and native deletion/retyping.
- Remove mandatory AXValue, writable selection-range, and range-reading capabilities from the correction path. A lightweight text/password focus check remains, with cancellation when input or context changes.
- Preserve clipboard contents through correction Copy/Paste and keep internal writes out of History and Paste Stack. Do not retry after sending a replacement.

Enable manual layout correction in Settings and tap the left Option key after typing, or select text before the tap. Correction uses supported static keyboard layouts enabled in macOS. Password/Secure Input fields and IME composition are excluded.

While correction is enabled, Qipli holds up to 256 recent physical keys with Shift/Caps metadata in memory. The buffer expires after five seconds of inactivity and is cleared on navigation, clicks, context changes, or disabling the feature. An explicit repeated correction can retain its fragment for up to 30 seconds to cycle layouts. Neither keys nor corrected text are written to diagnostics or sent over the network.

The two replacement transports were verified in Final Cut's effects-search field. Other Final Cut fields, installed Option/cycling behavior, and the wider compatibility matrix remain user acceptance checks. The caret stays at the end of the replacement; Undo grouping depends on the editor. Sending input does not prove that every target accepted it, and an interrupted replacement should be checked before retrying.

Existing History, favorites, shortcuts, Accessibility permissions, and diagnostic preferences are preserved. This release does not change the database schema. Optional diagnostics remain off by default and stay local.
