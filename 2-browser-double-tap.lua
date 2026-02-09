-- KOReader userpatch to require double-tap to open books in file browser
-- Prevents accidental book opening with a single tap
-- Configurable double-tap timeout in settings menu

local FileManager = require("apps/filemanager/filemanager")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local UIManager = require("ui/uimanager")
local SpinWidget = require("ui/widget/spinwidget")
local time = require("ui/time")
local _ = require("gettext")

local config_default = {
    require_double_tap = true,
    timeout_ms = 500,  -- milliseconds
}

local function load_config()
    return G_reader_settings:readSetting("browser_double_tap", config_default)
end

local config = load_config()

local function handleDoubleTapFileSelect(file_manager, item, orig_onFileSelect_func)
    -- If double-tap is disabled, use original behavior
    if not config.require_double_tap then
        return orig_onFileSelect_func(item)
    end

    -- If in selection mode, use original behavior (toggle selection)
    if file_manager.selected_files then
        return orig_onFileSelect_func(item)
    end

    -- Only apply double-tap to files, not folders
    if not item.is_file then
        return orig_onFileSelect_func(item)
    end

    local current_time = time.now()
    local timeout_fts = time.ms(config.timeout_ms)

    local time_since_last_tap_fts
    if file_manager.last_tap_time then
        time_since_last_tap_fts = current_time - file_manager.last_tap_time
    else
        time_since_last_tap_fts = timeout_fts * 2  -- Force first tap
    end

    if file_manager.last_tap_file == item.path and time_since_last_tap_fts < timeout_fts then
        file_manager:openFile(item.path)
        file_manager.last_tap_file = nil
        file_manager.last_tap_time = nil
    else
        file_manager.last_tap_file = item.path
        file_manager.last_tap_time = current_time
    end

    return true
end

local orig_FileManager_setupLayout = FileManager.setupLayout

function FileManager:setupLayout()
    orig_FileManager_setupLayout(self)

    local file_chooser = self.file_chooser
    local file_manager = self

    if file_chooser and not file_chooser._orig_onFileSelect then
        file_chooser._orig_onFileSelect = file_chooser.onFileSelect
    end

    if file_chooser then
        function file_chooser:onFileSelect(item)
            local orig_func = file_chooser._orig_onFileSelect
            return handleDoubleTapFileSelect(file_manager, item, function(itm)
                return orig_func(self, itm)
            end)
        end
    end
end

local function patchCoverBrowser()
    local ok, MosaicMenu = pcall(require, "mosaicmenu")
    if not ok or not MosaicMenu then
        return
    end

    if not MosaicMenu._orig_onFileSelect then
        MosaicMenu._orig_onFileSelect = MosaicMenu.onFileSelect
    end

    function MosaicMenu:onFileSelect(item)
        local file_manager = self.ui
        local orig_func = MosaicMenu._orig_onFileSelect
        return handleDoubleTapFileSelect(file_manager, item, function(itm)
            return orig_func(self, itm)
        end)
    end
end

patchCoverBrowser()

local orig_FileManager_init = FileManager.init

function FileManager:init()
    orig_FileManager_init(self)
    patchCoverBrowser()
end

local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

function FileManagerMenu:setUpdateItemTable()
    table.insert(FileManagerMenuOrder.filemanager_settings, "browser_double_tap")

    self.menu_items.browser_double_tap = {
        text = _("Double-tap to open books"),
        separator = true,
        sub_item_table = {
            {
                text = _("Require double-tap to open"),
                checked_func = function()
                    return config.require_double_tap
                end,
                callback = function()
                    config.require_double_tap = not config.require_double_tap
                    G_reader_settings:saveSetting("browser_double_tap", config)
                end,
            },
            {
                text = _("Double-tap timeout (ms)"),
                keep_menu_open = true,
                enabled_func = function()
                    return config.require_double_tap
                end,
                callback = function(touchmenu_instance)
                    local spin_widget = SpinWidget:new{
                        title_text = _("Double-tap timeout (milliseconds)"),
                        info_text = _("Maximum time between taps to register as double-tap"),
                        value = config.timeout_ms,
                        value_min = 200,
                        value_max = 1000,
                        value_step = 50,
                        value_hold_step = 100,
                        callback = function(spin)
                            config.timeout_ms = spin.value
                            G_reader_settings:saveSetting("browser_double_tap", config)
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
            },
        },
    }

    orig_FileManagerMenu_setUpdateItemTable(self)
end
