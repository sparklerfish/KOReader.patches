--[[
    Keeps the text of reflowable documents on a grid of whole lines,
    so pages don't end with a partial line's worth of leftover space.

    Needs KOReader v2026.07.2-26 (nightly of 2026-08-03) or later: its
    crengine is the first to know the "urlh" CSS unit (koreader/crengine#710,
    brought in by koreader/koreader#15798). On older versions the patch
    refuses to load, and Patch Management marks it as failed.
]]

local Version = require("version")

local OLDEST_SUPPORTED_KOREADER_VERSION = "v2026.07.2-26"

if (Version:getNormalizedCurrentVersion() or 0) < Version:getNormalizedVersion(OLDEST_SUPPORTED_KOREADER_VERSION) then
    error("needs KOReader " .. OLDEST_SUPPORTED_KOREADER_VERSION .. " or later, this is "
        .. (Version:getCurrentRevision() or "an unknown version"), 0)
end

local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
local Screen = require("device").screen
local util = require("util")

local SMALLEST_SPACING_IN_LINES_KEPT_AS_A_FULL_LINE = 0.3
local LARGEST_FONT_SIZE_IN_LINES_SET_ON_A_SINGLE_LINE = 1.1
local ASSUMED_FONT_HEIGHT_IN_EM = 1.3

local UNIFORM_LINE_HEIGHT_CSS = [[
* { line-height: inherit !important; }
DocFragment, FictionBook, html, body { line-height: 1urlh !important; }
body { -cr-hint: strut-confined; }
]]

local HORIZONTAL_RULE_ON_A_GRID_LINE_CSS = [[
hr { box-sizing: border-box; height: 1urlh; border-width: 1px 0 0 0; margin-top: 1urlh; margin-bottom: 0; page-break-inside: avoid; }
]]

-- From our user stylesheet, only !important declarations override the book's
-- own rules in crengine (whatever their specificity).  But they would then also
-- override style="" attributes, which we can't see.  So each snapped copy of a
-- book rule skips the elements whose style="" sets what that copy sets.
local INLINE_STYLE_GUARD_OF_PROPERTY = {
    ["margin-top"] = ':not([style*="margin" i])',
    ["margin-bottom"] = ':not([style*="margin" i])',
    ["padding-top"] = ':not([style*="padding" i])',
    ["padding-bottom"] = ':not([style*="padding" i])',
    ["height"] = ':not([style*="height" i])',
}

-- Style tweaks are !important too, and must keep winning over the snapped
-- copies of the book's rules, as they won over the book's rules themselves.
local APPLIED_AFTER_ALL_OTHER_RULES = "-cr-hint: late; "

local GRID_RELEVANT_CONDITION = "-cr-only-if"

local IS_LEGACY_SINGLE_COLON_PSEUDO_ELEMENT = {
    ["before"] = true,
    ["after"] = true,
    ["first-letter"] = true,
    ["first-line"] = true,
}

local IS_AT_RULE_WRAPPING_RULES = {
    ["@media"] = true,
    ["@supports"] = true,
}

local VERTICAL_SIDES_OF_SHORTHAND = {
    margin = { "margin-top", "margin-bottom" },
    padding = { "padding-top", "padding-bottom" },
}

local IS_VERTICAL_LONGHAND = {
    ["margin-top"] = true,
    ["margin-bottom"] = true,
    ["padding-top"] = true,
    ["padding-bottom"] = true,
    ["height"] = true,
}

local IS_FONT_RELATIVE_UNIT = {
    em = true,
    ex = true,
    ch = true,
    lh = true,
}

local FONT_SCALE_PER_FONT_RELATIVE_UNIT = {
    ["em"] = 1,
    ["%"] = 0.01,
    ["ex"] = 0.5,
    ["ch"] = 0.5,
}

local FONT_SCALE_OF_KEYWORD = {
    ["xx-small"] = 0.6,
    ["x-small"] = 0.75,
    ["small"] = 0.89,
    ["medium"] = 1,
    ["large"] = 1.2,
    ["x-large"] = 1.5,
    ["xx-large"] = 2,
    ["smaller"] = 0.83,
    ["larger"] = 1.2,
}

local function textColumnWidth(document)
    local margins = document:getPageMargins()
    return (Screen:getWidth() - margins.left - margins.right) / document:getVisiblePageCount()
end

local function linesPerCssUnit(document)
    local configurable = document.configurable
    local font_size_px = document:getFontSize()
    local line_height_px = font_size_px * ASSUMED_FONT_HEIGHT_IN_EM * configurable.line_spacing / 100
    local screen_px_per_css_px = configurable.render_dpi > 0 and configurable.render_dpi / 96 or 1
    local css_px = screen_px_per_css_px / line_height_px
    local em = font_size_px / line_height_px
    return {
        ["em"] = em,
        ["rem"] = em,
        ["urem"] = em,
        ["ex"] = em / 2,
        ["rex"] = em / 2,
        ["ch"] = em / 2,
        ["rch"] = em / 2,
        ["px"] = css_px,
        ["pt"] = css_px * 96 / 72,
        ["pc"] = css_px * 16,
        ["in"] = css_px * 96,
        ["cm"] = css_px * 96 / 2.54,
        ["mm"] = css_px * 96 / 25.4,
        ["q"] = css_px * 96 / 25.4 / 4,
        ["%"] = textColumnWidth(document) / 100 / line_height_px,
        ["vw"] = Screen:getWidth() / 100 / line_height_px,
        ["vh"] = Screen:getHeight() / 100 / line_height_px,
        ["lh"] = 1,
        ["rlh"] = 1,
        ["urlh"] = 1,
    }
end

local function parseLength(value)
    local number, unit = value:match("^([+-]?%d*%.?%d+)([%a%%]*)$")
    if number then
        return tonumber(number), unit
    end
end

local function lengthInLines(value, lines_per_unit, font_scale)
    local number, unit = parseLength(value)
    if not number then return end
    if number == 0 then return 0 end
    local lines_per_this_unit = lines_per_unit[unit]
    if not lines_per_this_unit then return end
    if IS_FONT_RELATIVE_UNIT[unit] then
        lines_per_this_unit = lines_per_this_unit * font_scale
    end
    return number * lines_per_this_unit
end

local function fontScale(value, lines_per_unit)
    if FONT_SCALE_OF_KEYWORD[value] then
        return FONT_SCALE_OF_KEYWORD[value]
    end
    local number, unit = parseLength(value)
    if not number then return end
    if FONT_SCALE_PER_FONT_RELATIVE_UNIT[unit] then
        return number * FONT_SCALE_PER_FONT_RELATIVE_UNIT[unit]
    end
    if lines_per_unit[unit] then
        return number * lines_per_unit[unit] / lines_per_unit.rem
    end
end

local function wholeLines(lines)
    local whole = math.floor(math.abs(lines) + 0.5)
    if whole == 0 then
        return lines >= SMALLEST_SPACING_IN_LINES_KEPT_AS_A_FULL_LINE and 1 or 0
    end
    return lines < 0 and -whole or whole
end

local function inLineHeights(whole_lines)
    return whole_lines == 0 and "0" or whole_lines .. "urlh"
end

local function linePitchForFontScale(font_scale, lines_per_unit)
    local font_size_in_lines = font_scale * lines_per_unit.rem
    return math.max(1, math.ceil(font_size_in_lines / LARGEST_FONT_SIZE_IN_LINES_SET_ON_A_SINGLE_LINE))
end

local function parseDeclarations(declarations_css)
    local declarations = {}
    for declaration_css in declarations_css:gmatch("[^;]+") do
        local property, value = declaration_css:match("^%s*([%w-]+)%s*:%s*(.-)%s*$")
        if property then
            local value_without_priority, important_count = value:lower():gsub("%s*!%s*important$", "")
            table.insert(declarations, {
                property = property:lower(),
                value = value_without_priority,
                is_important = important_count > 0,
            })
        end
    end
    return declarations
end

local function priorityOf(declaration, snapping)
    return (snapping.makes_important or declaration.is_important) and " !important" or ""
end

local function individualSelectors(selectors)
    local individual = {}
    local nesting_depth = 0
    local selector_start = 1
    for position = 1, #selectors do
        local character = selectors:sub(position, position)
        if character == "(" or character == "[" then
            nesting_depth = nesting_depth + 1
        elseif character == ")" or character == "]" then
            nesting_depth = nesting_depth - 1
        elseif character == "," and nesting_depth == 0 then
            table.insert(individual, util.trim(selectors:sub(selector_start, position - 1)))
            selector_start = position + 1
        end
    end
    table.insert(individual, util.trim(selectors:sub(selector_start)))
    return individual
end

local function guarded(selector, guard)
    local subject, pseudo_element = selector:match("^(.-)(::[%w-]+)$")
    if not subject then
        local candidate_subject, name = selector:match("^(.-):([%w-]+)$")
        if candidate_subject and IS_LEGACY_SINGLE_COLON_PSEUDO_ELEMENT[name:lower()] then
            subject, pseudo_element = candidate_subject, ":" .. name
        end
    end
    if subject then
        return subject .. guard .. pseudo_element
    end
    return selector .. guard
end

local function scopedToFragments(selector, fragment_scope)
    if not fragment_scope then
        return selector
    end
    local after_html = selector:match("^[Hh][Tt][Mm][Ll](.*)$")
    if after_html and not after_html:find("^[%w_-]") then
        return "html" .. fragment_scope.on_fragment_itself .. after_html
    end
    return ":where(" .. fragment_scope.fragment .. ") " .. selector
end

local function rewrittenSelectors(individual_selectors, snapping, guard)
    local rewritten = {}
    for _, selector in ipairs(individual_selectors) do
        if guard ~= "" then
            selector = guarded(selector, guard)
        end
        table.insert(rewritten, scopedToFragments(selector, snapping.fragment_scope))
    end
    return table.concat(rewritten, ", ")
end

local function fontSizeOfRule(individual_selectors, declarations, snapping)
    local declared
    local conditions_so_far = {}
    for _, declaration in ipairs(declarations) do
        if declaration.property == GRID_RELEVANT_CONDITION then
            table.insert(conditions_so_far, GRID_RELEVANT_CONDITION .. ": " .. declaration.value .. "; ")
        elseif declaration.property == "font-size" then
            local scale = fontScale(declaration.value, snapping.lines_per_unit)
            if scale then
                declared = {
                    scale = scale,
                    is_declared = true,
                    is_important = declaration.is_important,
                    conditions_css = table.concat(conditions_so_far),
                }
            end
        end
    end
    if declared then
        for _, selector in ipairs(individual_selectors) do
            snapping.font_scale_of_selector[selector] = declared.scale
        end
        return declared
    end
    local largest_known_scale
    for _, selector in ipairs(individual_selectors) do
        local known_scale = snapping.font_scale_of_selector[selector]
        if known_scale and (not largest_known_scale or known_scale > largest_known_scale) then
            largest_known_scale = known_scale
        end
    end
    return { scale = largest_known_scale or 1, is_declared = false }
end

local function gridRelevantDeclarations(declarations)
    local relevant = {}
    for _, declaration in ipairs(declarations) do
        local shorthand_sides = VERTICAL_SIDES_OF_SHORTHAND[declaration.property]
        if IS_VERTICAL_LONGHAND[declaration.property] or declaration.property == GRID_RELEVANT_CONDITION then
            table.insert(relevant, declaration)
        elseif shorthand_sides then
            local sides = {}
            for side in declaration.value:gmatch("%S+") do
                table.insert(sides, side)
            end
            if sides[1] then
                table.insert(relevant, { property = shorthand_sides[1], value = sides[1], is_important = declaration.is_important })
                table.insert(relevant, { property = shorthand_sides[2], value = sides[3] or sides[1], is_important = declaration.is_important })
            end
        end
    end
    return relevant
end

local function setsWidth(declarations)
    for _, declaration in ipairs(declarations) do
        if declaration.property == "width" and declaration.value ~= "auto" then
            return true
        end
    end
    return false
end

local function isAppliedLate(declarations)
    for _, declaration in ipairs(declarations) do
        if declaration.property == "-cr-hint" and declaration.value:find("late", 1, true) then
            return true
        end
    end
    return false
end

local function snappedSpacingCss(declaration, font_scale, snapping)
    local lines = lengthInLines(declaration.value, snapping.lines_per_unit, font_scale)
    if lines then
        return declaration.property .. ": " .. inLineHeights(wholeLines(lines)) .. priorityOf(declaration, snapping)
    end
end

local function snappedEmptyBoxHeightCss(declaration, font_scale, snapping)
    if declaration.value:find("%", 1, true) then return end
    local lines = lengthInLines(declaration.value, snapping.lines_per_unit, font_scale)
    if lines and lines >= SMALLEST_SPACING_IN_LINES_KEPT_AS_A_FULL_LINE then
        return "height: " .. inLineHeights(wholeLines(lines)) .. priorityOf(declaration, snapping)
            .. "; page-break-inside: avoid" .. priorityOf(declaration, snapping)
    end
end

local function snappedCss(declaration, font_scale, rule_sets_width, snapping)
    if declaration.property == "height" then
        if rule_sets_width then return end
        return snappedEmptyBoxHeightCss(declaration, font_scale, snapping)
    end
    return snappedSpacingCss(declaration, font_scale, snapping)
end

local function snapRule(selectors, declarations_css, snapping, output)
    local individual_selectors = individualSelectors(selectors)
    local declarations = parseDeclarations(declarations_css)
    local font_size = fontSizeOfRule(individual_selectors, declarations, snapping)
    local rule_sets_width = setsWidth(declarations)
    local late_css = (snapping.applies_late or isAppliedLate(declarations)) and APPLIED_AFTER_ALL_OTHER_RULES or ""

    local guards = {}
    local grid_css_of_guard = {}
    local conditions_so_far = {}
    for _, declaration in ipairs(gridRelevantDeclarations(declarations)) do
        if declaration.property == GRID_RELEVANT_CONDITION then
            local condition_css = GRID_RELEVANT_CONDITION .. ": " .. declaration.value
            table.insert(conditions_so_far, condition_css)
            for _, guard in ipairs(guards) do
                table.insert(grid_css_of_guard[guard], condition_css)
            end
        else
            local guard = snapping.guards_inline_styles and INLINE_STYLE_GUARD_OF_PROPERTY[declaration.property] or ""
            if not grid_css_of_guard[guard] then
                table.insert(guards, guard)
                grid_css_of_guard[guard] = { unpack(conditions_so_far) }
            end
            table.insert(grid_css_of_guard[guard], snappedCss(declaration, font_size.scale, rule_sets_width, snapping)
                or declaration.property .. ": " .. declaration.value .. priorityOf(declaration, snapping))
        end
    end

    for _, guard in ipairs(guards) do
        table.insert(output, rewrittenSelectors(individual_selectors, snapping, guard)
            .. " { " .. late_css .. table.concat(grid_css_of_guard[guard], "; ") .. "; }")
    end
    if font_size.is_declared then
        local line_pitch = linePitchForFontScale(font_size.scale, snapping.lines_per_unit)
        local line_pitch_late_css = snapping.applies_late and font_size.is_important and APPLIED_AFTER_ALL_OTHER_RULES or ""
        table.insert(output, rewrittenSelectors(individual_selectors, snapping, "") .. " { " .. line_pitch_late_css
            .. font_size.conditions_css .. "-cr-only-if: not-inline; line-height: " .. line_pitch .. "urlh !important; }")
    end
end

local function closingBracePosition(css, opening_brace_position)
    local depth = 0
    local position = opening_brace_position
    while true do
        local found_position, _, character = css:find("([{}\"'])", position)
        if not found_position then
            return #css + 1
        end
        if character == "{" then
            depth = depth + 1
        elseif character == "}" then
            depth = depth - 1
            if depth == 0 then
                return found_position
            end
        else
            found_position = css:find(character, found_position + 1, true) or #css
        end
        position = found_position + 1
    end
end

local function directoryOf(path)
    return path:match("^(.*)/[^/]*$") or ""
end

local function resolvePath(directory, relative_path)
    local segments = {}
    for segment in (directory .. "/" .. relative_path):gmatch("[^/]+") do
        if segment == ".." then
            table.remove(segments)
        elseif segment ~= "." then
            table.insert(segments, segment)
        end
    end
    local root = directory:sub(1, 1) == "/" and "/" or ""
    return root .. table.concat(segments, "/")
end

local snapStylesheetFile

local function snapCss(css, directory, snapping, output)
    css = css:gsub("/%*.-%*/", " ")
    local position = 1
    while true do
        local delimiter_position = css:find("[{;]", position)
        if not delimiter_position then break end
        local prelude = util.trim(css:sub(position, delimiter_position - 1))
        if css:sub(delimiter_position, delimiter_position) == ";" then
            local imported_path = prelude:match("^@import%s+url%(%s*[\"']?([^\"')]+)")
                or prelude:match("^@import%s+[\"']([^\"']+)")
            if imported_path and directory then
                snapStylesheetFile(resolvePath(directory, imported_path), snapping, output)
            end
            position = delimiter_position + 1
        else
            local closing_position = closingBracePosition(css, delimiter_position)
            local block = css:sub(delimiter_position + 1, closing_position - 1)
            if IS_AT_RULE_WRAPPING_RULES[prelude:match("^@[%w-]+") or ""] then
                local nested_output = {}
                snapCss(block, directory, snapping, nested_output)
                if #nested_output > 0 then
                    table.insert(output, prelude .. " {\n" .. table.concat(nested_output, "\n") .. "\n}")
                end
            elseif prelude ~= "" and not prelude:find("^@") then
                snapRule(prelude, block, snapping, output)
            end
            position = closing_position + 1
        end
    end
end

snapStylesheetFile = function(path, snapping, output)
    local snapped_key = (snapping.fragment_scope and snapping.fragment_scope.fragment or "") .. "\n" .. path
    if snapping.already_snapped[snapped_key] then return end
    snapping.already_snapped[snapped_key] = true
    local css = snapping.readFile(path)
    if css then
        snapCss(css, directoryOf(path), snapping, output)
    end
end

local function readLocalFile(path)
    local file = io.open(path, "r")
    if not file then return end
    local content = file:read("*all")
    file:close()
    return content
end

local function bookFileReader(document)
    local content_of_path = {}
    return function(path)
        if content_of_path[path] == nil then
            content_of_path[path] = document:getDocumentFileContent(path)
                or document:getDocumentFileContent(util.urlDecode(path))
                or false
        end
        return content_of_path[path] or nil
    end
end

-- crengine applies each of the book's stylesheets only while styling the
-- DocFragments (the book's HTML files) that link to it, while our snapped
-- copies go into the user stylesheet that applies everywhere. So we note
-- which fragments use each stylesheet, to scope its copies to them.
local function bookStylesheetSources(document)
    local sources = {}
    local source_of_key = {}
    local fragment_ids = {}
    local function addSource(key, source, fragment_id)
        local existing = source_of_key[key]
        if not existing then
            existing = source
            existing.fragment_ids = {}
            existing.is_used_by_fragment = {}
            source_of_key[key] = existing
            table.insert(sources, existing)
        end
        if not fragment_id then
            existing.is_used_by_unknown_fragment = true
        elseif not existing.is_used_by_fragment[fragment_id] then
            existing.is_used_by_fragment[fragment_id] = true
            table.insert(existing.fragment_ids, fragment_id)
        end
    end

    local fragment_number = 1
    while document:isXPointerInDocument("/body/DocFragment[" .. fragment_number .. "]") do
        local xpointer = "/body/DocFragment[" .. fragment_number .. "]"
        local opening_tag = document:getHTMLFromXPointers(xpointer, xpointer, 0, false) or ""
        opening_tag = opening_tag:match("^<DocFragment[^>]*>") or ""
        local function attribute(name)
            local value = opening_tag:match("%s" .. name .. "=\"([^\"]*)\"")
            return value and util.htmlEntitiesToUtf8(value)
        end
        local fragment_id = attribute("id")
        if fragment_id then
            table.insert(fragment_ids, fragment_id)
        end
        local linked_path = attribute("StyleSheet")
        if linked_path then
            addSource("file\n" .. linked_path, { path = linked_path }, fragment_id)
        end
        local inline_css = document:getTextFromXPointer(xpointer .. "/stylesheet")
        if inline_css and inline_css ~= "" then
            local html_path = attribute("Source")
            local directory = html_path and directoryOf(html_path)
            addSource("inline\n" .. (directory or "") .. "\n" .. inline_css, { css = inline_css, directory = directory }, fragment_id)
        end
        fragment_number = fragment_number + 1
    end

    if fragment_number == 1 then
        for _, xpointer in ipairs({ "/html/body/stylesheet", "/FictionBook/stylesheet" }) do
            local inline_css = document:getTextFromXPointer(xpointer)
            if inline_css and inline_css ~= "" then
                addSource("inline\n\n" .. inline_css, { css = inline_css }, nil)
            end
        end
    end
    return sources, fragment_ids
end

local function fragmentScope(source, all_fragment_ids)
    if source.is_used_by_unknown_fragment or #source.fragment_ids >= #all_fragment_ids then
        return nil
    end
    local function idList(ids)
        local id_selectors = {}
        for _, id in ipairs(ids) do
            table.insert(id_selectors, "#" .. id)
        end
        return table.concat(id_selectors, ", ")
    end
    if #source.fragment_ids <= #all_fragment_ids / 2 then
        local ids = idList(source.fragment_ids)
        return { fragment = "DocFragment:is(" .. ids .. ")", on_fragment_itself = ":where(" .. ids .. ")" }
    end
    local unused_ids = {}
    for _, id in ipairs(all_fragment_ids) do
        if not source.is_used_by_fragment[id] then
            table.insert(unused_ids, id)
        end
    end
    local ids = idList(unused_ids)
    return { fragment = "DocFragment:not(" .. ids .. ")", on_fragment_itself = ":where(:not(" .. ids .. "))" }
end

local function lineGridCss(style_tweak, with_book_styles, tweaks_css)
    local document = style_tweak.ui.document
    local lines_per_unit = linesPerCssUnit(document)
    local font_scale_of_selector = {}
    local output = { UNIFORM_LINE_HEIGHT_CSS }

    snapStylesheetFile(style_tweak.ui.typeset.css, {
        lines_per_unit = lines_per_unit,
        font_scale_of_selector = font_scale_of_selector,
        already_snapped = {},
        readFile = readLocalFile,
    }, output)
    table.insert(output, HORIZONTAL_RULE_ON_A_GRID_LINE_CSS)

    if with_book_styles then
        if not style_tweak.line_grid_book_sources then
            style_tweak.line_grid_book_sources, style_tweak.line_grid_fragment_ids = bookStylesheetSources(document)
            style_tweak.line_grid_read_book_file = bookFileReader(document)
        end
        local already_snapped = {}
        for _, source in ipairs(style_tweak.line_grid_book_sources) do
            local book_snapping = {
                lines_per_unit = lines_per_unit,
                font_scale_of_selector = font_scale_of_selector,
                makes_important = true,
                guards_inline_styles = true,
                fragment_scope = fragmentScope(source, style_tweak.line_grid_fragment_ids),
                already_snapped = already_snapped,
                readFile = style_tweak.line_grid_read_book_file,
            }
            if source.path then
                snapStylesheetFile(source.path, book_snapping, output)
            else
                snapCss(source.css, source.directory, book_snapping, output)
            end
        end
    end

    local tweaks_output = {}
    if tweaks_css then
        snapCss(tweaks_css, nil, {
            lines_per_unit = lines_per_unit,
            font_scale_of_selector = font_scale_of_selector,
            applies_late = true,
            already_snapped = {},
        }, tweaks_output)
    end
    return table.concat(output, "\n"), table.concat(tweaks_output, "\n")
end

local function lineGridInputs(style_tweak, tweaks_css)
    local document = style_tweak.ui.document
    local configurable = document.configurable
    local margins = document:getPageMargins()
    return table.concat({
        tostring(style_tweak.ui.typeset.css),
        tostring(configurable.embedded_css),
        document:getFontSize(),
        configurable.line_spacing,
        configurable.render_dpi,
        Screen:getWidth(),
        Screen:getHeight(),
        margins.left,
        margins.right,
        document:getVisiblePageCount(),
        tweaks_css or "",
    }, "\n")
end

local original_getCssText = ReaderStyleTweak.getCssText
function ReaderStyleTweak:getCssText()
    local tweaks_css = original_getCssText(self)
    if not self.line_grid_document_is_loaded then
        return tweaks_css
    end
    local inputs = lineGridInputs(self, tweaks_css)
    if self.line_grid_css_built_for ~= inputs then
        local with_book_styles = self.ui.document.configurable.embedded_css == 1
        self.line_grid_css, self.line_grid_tweaks_css = lineGridCss(self, with_book_styles, tweaks_css)
        self.line_grid_css_built_for = inputs
    end
    return table.concat({ self.line_grid_css, tweaks_css or "", self.line_grid_tweaks_css }, "\n")
end

function ReaderStyleTweak:refreshLineGrid()
    if self.line_grid_document_is_loaded and self.line_grid_css_built_for ~= lineGridInputs(self, original_getCssText(self)) then
        self.ui.document:setStyleSheet(self.ui.typeset.css, self:getCssText())
    end
end

local original_onPreRenderDocument = ReaderStyleTweak.onPreRenderDocument
function ReaderStyleTweak:onPreRenderDocument(...)
    self.line_grid_document_is_loaded = true
    self.ui.document:setStyleSheet(self.ui.typeset.css, self:getCssText())
    if original_onPreRenderDocument then
        return original_onPreRenderDocument(self, ...)
    end
end

-- Every change that re-renders the book (font size, line spacing, margins,
-- zoom, rotation, embedded styles...) goes through here, before crengine
-- re-renders: rebuild the grid if what it was computed from has changed.
local original_onUpdatePos = ReaderRolling.onUpdatePos
function ReaderRolling:onUpdatePos(...)
    if self.ui.styletweak and self.ui.styletweak.refreshLineGrid then
        self.ui.styletweak:refreshLineGrid()
    end
    return original_onUpdatePos(self, ...)
end
