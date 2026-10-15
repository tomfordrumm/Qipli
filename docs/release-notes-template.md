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

- Paste plain text from History with Shift-double-click, alongside Shift-Enter. Regular double-click keeps saved formatting.
- Correct keyboard layout for selections up to 12,288 UTF-16 units, preserving the existing safety checks and native Undo behavior.
- Show correction errors in a brief, nonactivating Top Notch panel that closes automatically.
- Add optional local diagnostic logs in Settings → General → Diagnostics. Logging is off by default. Enable it when investigating correction incidents; Show Logs opens the folder and Clear Logs removes the journals. Logs contain operation steps, fixed error codes and timings, without clipboard content, typed text, application/window identities, URLs or file paths. Logs stay on this Mac, rotate at 10 MiB, and expire after seven days while Qipli is running or on its next launch.

Manual layout correction requires a compatible editable field and supported static keyboard layouts. Secure fields and unsupported input methods are skipped. Correction is unavailable while Paste Stack, Finder Cut, or another Qipli input action is active. Diagnostics help investigate failures; they do not add support for incompatible fields.

Existing History and favorites are preserved; this release does not change the database schema.
