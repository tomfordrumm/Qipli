# DMG artwork

`install-background.svg` is the editable source. The committed PNG is the exact
Finder background used by `scripts/create-dmg.sh`; its 144 dpi metadata is part
of the layout contract because Finder displays the 1320×840 bitmap in a 660×420
point window.

Regenerate it on macOS with:

```sh
rsvg-convert --width 1320 --height 840 \
  --output release-assets/dmg/install-background.png \
  release-assets/dmg/install-background.svg
sips --setProperty dpiWidth 144 --setProperty dpiHeight 144 \
  release-assets/dmg/install-background.png
```
