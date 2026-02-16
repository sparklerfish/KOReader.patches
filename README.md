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

### [🞂 2-redacted-screensaver](2-redact-screensaver.lua)

A screensaver that shows the current page with random words/phrases covered by black "redaction" bars. 

* **Settings:** Toggle via Screen -> Sleep screen -> Wallpaper -> Use redacted screensaver when reading
* **Features:**
  * Supports EPUBs/rolling documents. Currently does not work with paged documents like PDFs (perhaps in a future update!)
  * Only applies while in reader view (i.e. while reading a compatible book); otherwise your regular screensaver will apply (i.e. in file browser or while reading a PDF).
