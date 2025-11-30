--[[
    This user patch updates the file browser frontlight
    widget in real-time when the frontlight is adjusted.
    Works with Project Title and 2-filemanager-titlebar patch.
--]]

local userpatch = require("userpatch")

local function patchFrontlightUpdate()
    local UIManager = require("ui/uimanager")
    local FileManager = require("apps/filemanager/filemanager")

    local function updateFileManagerFooter(target_widget)
        if target_widget and target_widget.file_chooser and target_widget.file_chooser.updatePageInfo then
            target_widget.file_chooser:updatePageInfo()
            UIManager:setDirty(target_widget, function()
                return "ui", target_widget.dimen
            end)
            return
        end

        -- Fallback: search window stack (uses internal API, may break in future versions)
        local window_stack = UIManager._window_stack
        if not window_stack then return end

        for i = #window_stack, 1, -1 do
            local widget = window_stack[i].widget
            if widget and widget.file_chooser and widget.file_chooser.updatePageInfo then
                widget.file_chooser:updatePageInfo()
                UIManager:setDirty(widget, function()
                    return "ui", widget.dimen
                end)
                return
            end
        end
    end

    if FileManager and not FileManager._frontlight_patch_applied then
        FileManager._frontlight_patch_applied = true

        -- Preserve existing handler (e.g., from 2-filemanager-titlebar.lua)
        local orig_onFrontlightStateChanged = FileManager.onFrontlightStateChanged

        FileManager.onFrontlightStateChanged = function(self)
            if orig_onFrontlightStateChanged then
                orig_onFrontlightStateChanged(self)
            end
            updateFileManagerFooter(self)
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchFrontlightUpdate)
