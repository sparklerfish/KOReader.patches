# KOReader Userpatches

This repository contains userpatches for KOReader and/or its plugins.

## Installation

1. If it doesn't already exist, create `koreader/patches` directory

2. Download the `.lua` patch file and copy it to the `koreader/patches` directory

3. Restart KOReader

You can see the list and status of your user patches and enable/disable them in `Patch Management`.

See the [KOReader documentation](https://koreader.rocks/user_guide/#L2-userpatches) for more information.

## Patches

### [🞂 2-browser-double-tap](2-browser-double-tap.lua)

Requires double-tap to open books in the file browser, preventing accidental book opening with a single tap.

* **Settings:** Accessible via the "Double-tap to open books" menu in File Manager settings.
* **Features:**
  * Toggle double-tap requirement on/off
  * Configurable timeout (200-1000ms, default 500ms)
  * Works with File Browser, Cover Browser, and Project: Title
  * Folders and selection mode still use single-tap

### [🞂 2-browser-frontlight-update](2-browser-frontlight-update.lua)

Updates Project: Title/Cover Browser frontlight widget in real time when frontlight is adjusted.

* **For use with Project: Title:** Requires [Project: Title](https://github.com/joshuacant/ProjectTitle) with "Replace folder name with device info" enabled.
* **For use with Cover Browser:** Requires [2-filemanager-titlebar](https://github.com/sebdelsol/KOReader.patches/blob/main/2-filemanager-titlebar.lua) patch.

### [🞂 2-snap-line-height](2-snap-line-height.lua)

Keeps the text of EPUBs and other reflowable books on a grid of whole lines, so every full page ends at the same place instead of leaving a different sliver of empty space at the bottom.

* **Requires:** KOReader v2026.07.2-26 (nightly of 2026-08-03) or later. On older versions the patch won't load, and Patch Management marks it with ⚠.
* **Features:**
  * Rounds vertical margins, padding and spacer heights to whole lines. This covers KOReader's stylesheet, the book's own styles and your style tweaks.
  * Gives all text the same line height. Larger headings take up two or more whole lines.
  * Superscripts and larger inline text don't push lines apart.
  * Your style tweaks still take priority over the book's styles.
* **Limitations:**
  * Images, borders, and elements whose inline style sets their own margins shift the rest of their page off the grid.
  * Line heights set by the book are ignored.
  * Books that set a small fixed font size get a full line of height for each line of text, so they look loosely spaced. The "Ignore publisher font sizes" style tweak (Style tweaks → Font size and families) helps with those.

### [🞂 2-z-redacted-screensaver](2-z-redacted-screensaver.lua)

A screensaver that shows the current page with random words/phrases covered by black "redaction" bars. 

* **Settings:** Toggle via Screen -> Sleep screen -> Wallpaper -> Use redacted screensaver when reading
* **Features:**
  * Supports EPUBs/rolling documents and PDFs/paged documents.
  * Only applies while in reader view (i.e. while reading a compatible book); otherwise your regular screensaver will apply (i.e. in file browser).
* **Compatibility note:** May not work if other patches that modify the screensaver functionality load after this one.  KOReader loads patches alphabetically, so if you're hitting issues and have a screensaver-related patch lower down, try renaming this to fall even later alphabetically.
