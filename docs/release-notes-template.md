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
shortcuts, a shared screen-edge setting for History and Paste Stack, an opt-in
Launch at Login control, manual update checks, and an off-by-default periodic
update check.

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

- Redesigned History and Paste Stack as black panels connected to the screen edge, with refined spacing, controls, and soft liquid expansion that settles gently.
- Choose Top, Right, Bottom, or Left in Settings → Appearance. One setting applies to both panels. Side panels show cards vertically, and History uses Up/Down navigation there.
- Remove the thin gap during opening by disabling the system window zoom underneath the custom animation. Reduce Motion keeps a short fade.
- Switch the keyboard layout immediately after correction is dispatched, before the clipboard restoration delay. Typing during that delay no longer turns a completed layout switch into a stale failure; the original clipboard is restored only while Qipli still owns it.
- Keep the last meaningful correction failure in optional local diagnostics and distinguish the stages and guards that interrupted a correction. Diagnostics remain off by default and contain no copied or corrected text.

Enable manual layout correction in Settings and tap the left Option key after typing, or select text before the tap. Correction requires a compatible editable field and supported static keyboard layouts enabled in macOS. Password/Secure Input fields and active IME composition are excluded.

The physical-key buffer is cleared on navigation, clicks, context changes, or disabling the feature. Neither keys nor corrected text are written to diagnostics or sent over the network.

Correction behavior, clipboard restoration, and Undo depend on the target editor. Full Chrome/Telegram/Final Cut, accessibility, and multi-display acceptance remains separate from local automated checks. If correction is interrupted after sending input, inspect the text before trying again. Undo grouping depends on the editor.

Existing History, favorites, shortcuts, and diagnostic preferences are retained. The screen edge defaults to Top. This release does not change the database schema or permission requirements.
