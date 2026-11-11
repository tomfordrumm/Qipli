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

- Avoid duplicate image History entries when Hex restores the previous clipboard after dictation. Detection applies when Qipli observes the temporary marked text followed by the same image. Repeated user copies remain separate entries.
- Layout correction now selects and verifies the previous word or cyclic result before replacing it with one paste. Losing Accessibility access before paste preserves the original text.
- If the selected range or copied text cannot be verified, correction stops and asks you to select the text explicitly. The selection may remain in place.

Existing History, favorites, shortcuts, and preferences are retained. This release does not change the database schema or permission requirements.
