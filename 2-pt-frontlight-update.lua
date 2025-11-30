--[[
    This user patch updates the Project: Title footer's frontlight widget
    in real-time when the frontlight is adjusted.
--]]

local userpatch = require("userpatch")

local function patchFrontlightUpdate()
    local Menu = require("ui/widget/menu")
    local UIManager = require("ui/uimanager")
    local FileManager = require("apps/filemanager/filemanager")

    local function updateFileManagerFooter()
        for i = #UIManager._window_stack, 1, -1 do
            local widget = UIManager._window_stack[i].widget
            if widget.file_chooser and widget.file_chooser.updatePageInfo then
                widget.file_chooser:updatePageInfo()
                UIManager:setDirty(widget, function()
                    return "ui", widget.dimen
                end)
                return
            end
        end
    end

    if Menu and not Menu._frontlight_patch_applied then
        Menu._frontlight_patch_applied = true
        Menu.onFrontlightStateChanged = function(self)
            if self.cur_folder_text then
                updateFileManagerFooter()
            end
        end
    end

    if FileManager and not FileManager._frontlight_patch_applied then
        FileManager._frontlight_patch_applied = true
        FileManager.onFrontlightStateChanged = function(self)
            if self.file_chooser then
                updateFileManagerFooter()
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchFrontlightUpdate)
