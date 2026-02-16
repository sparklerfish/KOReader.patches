--[[
    Redacted Screensaver Patch for KOReader

    Shows the current page with random words covered by black "redaction" bars.
    Works with EPUB, FB2, and other rolling documents.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local DocCache = require("document/doccache")
local Geom = require("ui/geometry")
local logger = require("logger")
local random = require("random")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

random.seed()

-- Configuration
local REDACTION_CHANCE = 0.35       -- 35% of words get redacted
local MIN_REDACTIONS = 5            -- minimum number of redactions
local MAX_REDACTIONS = 50           -- maximum number of redactions
local REDACTION_PADDING_H = 2       -- horizontal padding around words
local REDACTION_PADDING_V = 1       -- vertical padding around words

-- Additional constants
local MERGE_GAP_TOLERANCE = 20      -- Max gap between boxes to merge (pixels)
local PHRASE_SINGLE_PROB = 0.6      -- 60% chance of single word
local PHRASE_DOUBLE_PROB = 0.85     -- 85% cumulative for 1-2 words (25% for double)
                                    -- Remaining 15% for triple words

-- Settings key
local REDACTED_ENABLED_SETTING = "redactedscreensaver_enabled"

local RedactedScreensaverWidget = Widget:extend{
    ui = nil,
    document = nil,
    dimen = nil,
    redaction_boxes = nil,
}

function RedactedScreensaverWidget:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.redaction_boxes = {}
    self:calculateRedactions()
end

function RedactedScreensaverWidget:groupBoxesByLine(boxes, tolerance)
    local lines = {}

    for _, box in ipairs(boxes) do
        local found_line = false

        for _, line in ipairs(lines) do
            if math.abs(line.y - box.y) <= tolerance then
                table.insert(line.boxes, box)
                found_line = true
                break
            end
        end

        if not found_line then
            table.insert(lines, {
                y = box.y,
                boxes = {box}
            })
        end
    end

    return lines
end

function RedactedScreensaverWidget:calculateLineTolerance()
    local default_tolerance = 5

    if self.ui and self.ui.font and self.ui.font.size then
        local font_size = self.ui.font.size
        return math.max(3, math.floor(font_size * 0.25))
    end

    if self.ui and self.ui.rolling and self.ui.rolling.font_size then
        local font_size = self.ui.rolling.font_size
        return math.max(3, math.floor(font_size * 0.25))
    end

    return default_tolerance
end

function RedactedScreensaverWidget:buildCacheKey()
    local doc_file = self.document.file
    if not doc_file then return nil end

    local page_id
    if self.ui.paging then
        page_id = self.ui:getCurrentPage()
    elseif self.ui.rolling then
        if self.ui.view and self.ui.view.state and self.ui.view.state.page then
            page_id = self.ui.view.state.page
        end
    end

    if not page_id then return nil end

    local font_size = 0
    if self.ui.rolling and self.ui.rolling.font_size then
        font_size = self.ui.rolling.font_size
    end

    local rotation = Screen:getRotationMode() or 0

    local cache_key = string.format("redacted_boxes|%s|%s|f%d|r%d",
        doc_file, tostring(page_id), font_size, rotation)
    return cache_key
end

function RedactedScreensaverWidget:calculateRedactions()
    if not self.ui then
        logger.warn("RedactedScreensaver: No UI available")
        return
    end

    if not self.document then
        logger.warn("RedactedScreensaver: No document available")
        return
    end

    if not self.ui.view then
        logger.warn("RedactedScreensaver: No view available")
        return
    end

    local cache_key = self:buildCacheKey()
    if not cache_key then return end

    local cached = DocCache:check(cache_key)
    local boxes = nil

    if cached and cached.boxes then
        boxes = cached.boxes
    else
        local ok, result = pcall(function()
            if self.ui.rolling then
                return self:getRollingDocumentBoxes()
            end
            return {}
        end)

        if ok and result then
            boxes = result

            local MAX_CACHED_BOXES = 500
            if #boxes > MAX_CACHED_BOXES then
                logger.warn(string.format(
                    "RedactedScreensaver: Page has %d words, limiting cache to %d",
                    #boxes, MAX_CACHED_BOXES))
                local limited_boxes = {}
                for i = 1, MAX_CACHED_BOXES do
                    limited_boxes[i] = boxes[i]
                end
                boxes = limited_boxes
            end

            if #boxes > 0 then
                DocCache:insert(cache_key, {
                    boxes = boxes,
                    size = #boxes * 100,
                })
            end
        end
    end

    if boxes and #boxes > 0 then
        self:selectRandomRedactions(boxes)
    else
        logger.warn("RedactedScreensaver: No word boxes found")
    end
end

function RedactedScreensaverWidget:getRollingDocumentBoxes()
    local boxes = {}

    if not self.document then
        logger.warn("RedactedScreensaver: No document for rolling extraction")
        return boxes
    end

    -- Calculate adaptive grid step based on font size
    local font_size = 16  -- default fallback
    if self.ui.rolling and self.ui.rolling.font_size then
        font_size = self.ui.rolling.font_size
    end

    local step_x = math.max(60, math.floor(font_size * 6))
    local step_y = math.max(30, math.floor(font_size * 3))

    local seen_words = {}
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    for y = 0, screen_h, step_y do
        for x = 0, screen_w, step_x do
            local ok, word = pcall(self.document.getWordFromPosition, self.document, {x = x, y = y}, true)
            if ok and word and word.sbox then
                local sbox = word.sbox
                local key = string.format("%.0f_%.0f_%.0f_%.0f",
                    sbox.x or 0, sbox.y or 0, sbox.w or 0, sbox.h or 0)
                if not seen_words[key] and sbox.w and sbox.h and sbox.w > 0 and sbox.h > 0 then
                    seen_words[key] = true
                    table.insert(boxes, {
                        x = sbox.x,
                        y = sbox.y,
                        w = sbox.w,
                        h = sbox.h,
                        word = word.word or "",
                    })
                end
            end
        end
    end
    return boxes
end

function RedactedScreensaverWidget:selectRandomRedactions(boxes)
    if #boxes == 0 then return end

    -- Group boxes into lines based on Y coordinate
    local line_tolerance = self:calculateLineTolerance()
    local lines = self:groupBoxesByLine(boxes, line_tolerance)

    for _, line in ipairs(lines) do
        table.sort(line.boxes, function(a, b) return a.x < b.x end)
    end

    for i = #lines, 2, -1 do
        local j = math.random(1, i)
        lines[i], lines[j] = lines[j], lines[i]
    end

    local redaction_count = 0
    local max_redactions = math.min(MAX_REDACTIONS, #boxes)

    for _, line in ipairs(lines) do
        if redaction_count >= max_redactions then
            break
        end

        local line_boxes = line.boxes
        if #line_boxes > 0 then
            local i = 1
            while i <= #line_boxes and redaction_count < max_redactions do
                if math.random() < REDACTION_CHANCE then
                    local rand = math.random()
                    local phrase_length
                    if rand < PHRASE_SINGLE_PROB then
                        phrase_length = 1  -- 60% single word
                    elseif rand < PHRASE_DOUBLE_PROB then
                        phrase_length = 2  -- 25% two words
                    else
                        phrase_length = 3  -- 15% three words
                    end
                    phrase_length = math.min(phrase_length, #line_boxes - i + 1)
                    for j = 0, phrase_length - 1 do
                        if i + j <= #line_boxes and redaction_count < max_redactions then
                            table.insert(self.redaction_boxes, line_boxes[i + j])
                            redaction_count = redaction_count + 1
                        end
                    end
                    i = i + phrase_length
                else
                    i = i + 1
                end
            end
        end
    end

    if redaction_count < MIN_REDACTIONS then
        for _, line in ipairs(lines) do
            if redaction_count >= MIN_REDACTIONS then
                break
            end
            for _, box in ipairs(line.boxes) do
                if math.random() < 0.5 and redaction_count < MAX_REDACTIONS then
                    table.insert(self.redaction_boxes, box)
                    redaction_count = redaction_count + 1
                end
            end
        end
    end

    self:mergeConsecutiveRedactions()
end

function RedactedScreensaverWidget:mergeConsecutiveRedactions()
    if #self.redaction_boxes == 0 then return end

    -- Group redactions by line (similar Y coordinate)
    local line_tolerance = self:calculateLineTolerance()
    local lines = self:groupBoxesByLine(self.redaction_boxes, line_tolerance)

    local merged_boxes = {}
    for _, line in ipairs(lines) do
        table.sort(line.boxes, function(a, b) return a.x < b.x end)
        local i = 1
        while i <= #line.boxes do
            local current = line.boxes[i]
            local merge_box = {
                x = current.x,
                y = current.y,
                w = current.w,
                h = current.h,
            }
            local j = i + 1
            while j <= #line.boxes do
                local next_box = line.boxes[j]
                local gap = next_box.x - (merge_box.x + merge_box.w)
                if gap <= MERGE_GAP_TOLERANCE then
                    local right_edge = math.max(merge_box.x + merge_box.w, next_box.x + next_box.w)
                    merge_box.w = right_edge - merge_box.x
                    merge_box.h = math.max(merge_box.h, next_box.h)
                    j = j + 1
                else
                    break
                end
            end
            table.insert(merged_boxes, merge_box)
            i = j
        end
    end
    self.redaction_boxes = merged_boxes
end

function RedactedScreensaverWidget:paintTo(bb, x, y)
    local bb_width = bb:getWidth()
    local bb_height = bb:getHeight()

    for _, box in ipairs(self.redaction_boxes) do
        local rx = box.x - REDACTION_PADDING_H
        local ry = box.y - REDACTION_PADDING_V
        local rw = box.w + (REDACTION_PADDING_H * 2)
        local rh = box.h + (REDACTION_PADDING_V * 2)

        local x1 = math.max(0, rx)
        local y1 = math.max(0, ry)
        local x2 = math.min(bb_width, rx + rw)
        local y2 = math.min(bb_height, ry + rh)

        rw = x2 - x1
        rh = y2 - y1

        if rw > 0 and rh > 0 then
            bb:paintRect(x1, y1, rw, rh, Blitbuffer.COLOR_BLACK)
        end
    end
end

------------------------------------------------------------
-- Screensaver Module Patching
------------------------------------------------------------

local Screensaver = require("ui/screensaver")

if not Screensaver._orig_setup then
    Screensaver._orig_setup = Screensaver.setup
    Screensaver._orig_show = Screensaver.show
    Screensaver._orig_cleanup = Screensaver.cleanup
    Screensaver._orig_modeExpectsPortrait = Screensaver.modeExpectsPortrait
end

local function shouldShowRedacted()
    -- Only use redacted if:
    -- 1. The toggle is enabled
    -- 2. We're currently in a rolling document (EPUB, FB2, etc.)
    -- 3. Not in a paged document (PDF, DjVu, etc.)
    local enabled = G_reader_settings:readSetting(REDACTED_ENABLED_SETTING) == true
    local ui = require("apps/reader/readerui").instance
    local in_rolling_document = ui and ui.document and ui.rolling and not ui.paging
    return enabled and in_rolling_document
end

Screensaver.setup = function(screensaver_self, event, event_message)
    Screensaver._orig_setup(screensaver_self, event, event_message)

    if shouldShowRedacted() then
        logger.info("RedactedScreensaver: Activating redacted screensaver")
        screensaver_self.screensaver_type = "redacted"
    end
end

Screensaver.show = function(screensaver_self)
    if screensaver_self.screensaver_type ~= "redacted" then
        return Screensaver._orig_show(screensaver_self)
    end

    local ui = require("apps/reader/readerui").instance
    if not ui then return end

    Device.screen_saver_mode = true

    local redacted_widget = RedactedScreensaverWidget:new{
        ui = ui,
        document = ui.document,
    }

    if Screen.bb then
        local ok, err = pcall(redacted_widget.paintTo,
                              redacted_widget,
                              Screen.bb, 0, 0)
        if not ok then
            logger.err("RedactedScreensaver: Failed to paint redactions:", err)
        end
    end

    local ScreenSaverWidget = require("ui/widget/screensaverwidget")

    local empty_widget = Widget:new{}
    empty_widget.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    screensaver_self.screensaver_widget = ScreenSaverWidget:new{
        widget = empty_widget,
        background = nil,  -- no background, keep existing screen content
        covers_fullscreen = true,
    }
    screensaver_self.screensaver_widget.modal = true

    UIManager:show(screensaver_self.screensaver_widget, "full")

    if Device:isTouchDevice() and
       G_reader_settings:readSetting("screensaver_delay") == "gesture" then
        local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
        screensaver_self.screensaver_lock_widget = ScreenSaverLockWidget:new{
            ui = ui,
        }
        UIManager:show(screensaver_self.screensaver_lock_widget)
    end
end

Screensaver.cleanup = function(screensaver_self)
    Screensaver._orig_cleanup(screensaver_self)
end

Screensaver.modeExpectsPortrait = function(screensaver_self)
    if screensaver_self.screensaver_type == "redacted" then
        return false  -- Keep current orientation
    end
    return Screensaver._orig_modeExpectsPortrait(screensaver_self)
end

------------------------------------------------------------
-- Menu Injection
------------------------------------------------------------

local orig_dofile = dofile

_G.dofile = function(filepath)
    local result = orig_dofile(filepath)

    if filepath and filepath:match("screensaver_menu%.lua$") then
        if result and result[1] and result[1].sub_item_table then
            local wallpaper_submenu = result[1].sub_item_table

            for _, item in ipairs(wallpaper_submenu) do
                if item.text and type(item.text) == "string" and item.text:find("redacted") then
                    _G.dofile = orig_dofile
                    return result
                end
            end

            -- Insert our checkbox after the screensaver type options (position 7)
            table.insert(wallpaper_submenu, 7, {
                text = _("Use redacted screensaver when reading"),
                help_text = _("When enabled, shows the current page with random words blacked out like a redacted document while reading a book. This overrides the wallpaper setting above when in reader mode."),
                checked_func = function()
                    return G_reader_settings:isTrue(REDACTED_ENABLED_SETTING)
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse(REDACTED_ENABLED_SETTING)
                end,
                separator = true,
            })

            logger.info("RedactedScreensaver: Successfully injected menu item into screensaver settings")
        end

        _G.dofile = orig_dofile
    end

    return result
end
