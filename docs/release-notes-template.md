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
values. Optional local diagnostics are off by default; when enabled they record
correction stages and the target application's bundle identifier on this Mac,
never clipboard content, and are never uploaded.

Source code and license: https://github.com/tomfordrumm/Qipli

## Changes

- Manual keyboard layout correction of a selection no longer refuses text containing punctuation keys such as `, . ; ' [ ] \` (for example б ю ж э х ъ ё in the Russian layout). Duplicate keypad and Caps Lock variants of these keys no longer make the mapping ambiguous.
- Layout correction now briefly waits for the copied text when an app adds it after clearing the clipboard, as Qt-based apps such as Telegram can, instead of refusing immediately. If another app changes the clipboard during this wait, the correction stops and leaves that clipboard content untouched.
- Opt-in local correction diagnostics now record which kind of input event discarded the recently typed word and the structure of an unsuccessful copy response (counts only). Diagnostics remain off by default and local-only, and never record clipboard content, keys, or text.

Existing History, favorites, shortcuts, and preferences are retained. This release does not change the database schema or permission requirements.
