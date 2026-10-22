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

- Restore keyboard input automatically after macOS disables the listener. Successful reconnects no longer consume a permanent retry budget; failed reconnects retry with a delay. Qipli shows a message while input is unavailable.
- Stop layout correction without deleting text when selection Copy fails. Recheck the focused field before Copy and replacement, including changes between fields in the same application.
- Replace buffered words using paced Backspace and native Paste. Prepare the clipboard before deleting text, preserve newer external copies, and never retry a partially dispatched correction.
- Recover word correction after an uncertain composition ends at a safe boundary. The in-memory buffer now lasts up to 30 seconds after typing, instead of five, and remains limited to 256 physical keys.

Enable manual layout correction in Settings and tap the left Option key after typing, or select text before the tap. Correction requires a compatible editable field and supported static keyboard layouts enabled in macOS. Password/Secure Input fields and active IME composition are excluded.

The physical-key buffer is cleared on navigation, clicks, context changes, or disabling the feature. Neither keys nor corrected text are written to diagnostics or sent over the network. Optional local diagnostics remain off by default; enable them in Settings → General → Diagnostics before reproducing an incident.

Chrome and Telegram compatibility, installed Option/cycling behavior, clipboard restoration, and Undo still need user acceptance testing for this version. Input dispatch is not proof that an editor accepted the replacement. If correction is interrupted after sending input, inspect the text before trying again. Undo grouping depends on the editor.

Existing History, favorites, shortcuts, Accessibility permissions, and diagnostic preferences are preserved. This release does not change the database schema.
