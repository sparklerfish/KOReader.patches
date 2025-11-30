--[[
    This user patch updates the Project: Title footer's frontlight widget
    in real-time when the frontlight is adjusted.
--]]

local userpatch = require("userpatch")

local function patchFrontlightUpdate()
    local UIManager = require("ui/uimanager")
    local FileManager = require("apps/filemanager/filemanager")

    local function updateFileManagerFooter(target_widget)
        -- If called with a specific widget that has file_chooser, use it directly
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
        FileManager.onFrontlightStateChanged = function(self)
            updateFileManagerFooter(self)
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchFrontlightUpdate)
