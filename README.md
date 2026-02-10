# KOReader Userpatches

This repository contains userpatches for KOReader and/or its plugins.

## Installation

See the [KOReader documentation](https://koreader.rocks/user_guide/#L2-userpatches).

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
