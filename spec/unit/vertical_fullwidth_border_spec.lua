--[[--
Vertical inline borders next to upright fullwidth text.

The text decoration belongs to the anchor's inline box. A descendant fullwidth
digit may have a larger font, but it must not move only its portion of the
decoration or the coincident border-right line.
--]]

describe("Vertical text: fullwidth inline border #vertical_fullwidth_border", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_fullwidth_border.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    it("draws an underlined bordered link without treating padding as text", function()
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
/* Match the small-font TOC case: a 90%/140% link must keep one
 * right-side Japanese sideline even after integer-pixel rounding. */
body { writing-mode: vertical-rl; font-size: 12px; }
p { margin: 1em; }
a { border-right: 1px solid; text-decoration: underline; }
a span { font-size: 1.4em; line-height: 1.2; }
a.plain { border-right: 0; }
</style></head><body>
<p><a href="#">第<span>１</span>章</a></p>
<p><a class="plain" href="#">甲<span>２</span>乙</a></p>
</body></html>]])
        f:close()

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local words = {}
        for x = Screen:getWidth() - 4, 4, -4 do
            for y = 4, Screen:getHeight() - 4, 4 do
                local word = readerui.document:getWordFromPosition({x=x, y=y})
                if word and word.sbox and (word.word == "第" or word.word == "１"
                        or word.word == "章" or word.word == "甲"
                        or word.word == "２" or word.word == "乙") then
                    words[word.word] = word.sbox
                end
            end
        end
        local found = assert(words["１"], "fullwidth digit was not rendered")
        print(string.format("[vertical_fullwidth_border] digit=(%d,%d %dx%d)",
            found.x, found.y, found.w, found.h))

        local first = assert(words["第"], "first anchor character was not rendered")
        local last = assert(words["章"], "last anchor character was not rendered")
        local y0 = math.min(first.y, found.y, last.y)
        local y1 = math.max(first.y + first.h, found.y + found.h, last.y + last.h)
        local span = y1 - y0
        local continuous_columns = {}
        local decorated_scan_left = math.min(first.x, found.x, last.x)
        local decorated_scan_right = math.min(Screen:getWidth() - 1,
            math.max(first.x + first.w, found.x + found.w, last.x + last.w) + 8)
        for x = decorated_scan_left, decorated_scan_right do
            local dark = 0
            for y = y0, y1 - 1 do
                local px = Screen.bb:getPixel(x, y)
                if px and px:getR() < 200 then dark = dark + 1 end
            end
            if dark >= span * 0.8 then
                table.insert(continuous_columns, x)
            end
        end
        print(string.format("[vertical_fullwidth_border] continuous_line_columns=%s",
            table.concat(continuous_columns, ",")))
        -- At small font sizes the 1px underline and the authored 1px border
        -- intentionally overlap, so one dark pixel column is sufficient.
        assert.is_true(#continuous_columns >= 1, "vertical underline was not continuous")
        -- The border and font-derived underline may form one or a few
        -- contiguous pixels, but must not split into visibly separate rules.
        assert.is_true(#continuous_columns <= 6,
            "underline and border-right formed an abnormally wide line")
        assert.are.equal(#continuous_columns,
            continuous_columns[#continuous_columns] - continuous_columns[1] + 1,
            "underline and border-right separated into a double line")
        local rightmost_glyph_edge = math.max(first.x + first.w, found.x + found.w,
            last.x + last.w)
        assert.is_true(continuous_columns[#continuous_columns] >= rightmost_glyph_edge - 1,
            "Japanese vertical underline was not placed on the right side")

        -- A continuous authored border can hide an underline that stops and
        -- restarts at descendant text-node boundaries. Check the exact rule
        -- columns in both whitespace gaps: every column detected along the
        -- link must remain dark while crossing each boundary.
        local first_end = first.y + first.h
        local digit_end = found.y + found.h
        local boundary_ys = {
            math.floor((first_end + found.y) / 2),
            math.floor((digit_end + last.y) / 2),
        }
        local boundary_widths = {}
        for _, boundary_y in ipairs(boundary_ys) do
            local width = 0
            for _, column_x in ipairs(continuous_columns) do
                local px = Screen.bb:getPixel(column_x, boundary_y)
                if px and px:getR() < 200 then width = width + 1 end
            end
            table.insert(boundary_widths, width)
            assert.are.equal(#continuous_columns, width,
                "underline was interrupted at a descendant text-node boundary")
        end
        print(string.format(
            "[vertical_fullwidth_border] boundary_widths=%s at y=%s",
            table.concat(boundary_widths, ","), table.concat(boundary_ys, ",")))

        -- A line displaced only alongside the larger descendant is shorter
        -- than the whole anchor, so the paragraph-wide scan above cannot see
        -- it. Compare the continuous columns in each glyph's own inline span.
        local function line_columns(box)
            local columns = {}
            local scan_left = box.x + math.floor(box.w * 0.55)
            for x = scan_left, box.x + box.w - 1 do
                local dark = 0
                for y = box.y, box.y + box.h - 1 do
                    local px = Screen.bb:getPixel(x, y)
                    if px and px:getR() < 200 then dark = dark + 1 end
                end
                if dark >= box.h * 0.75 then
                    columns[x] = true
                end
            end
            return columns
        end
        local outer = line_columns(first)
        local digit = line_columns(found)
        local displaced = {}
        for x in pairs(digit) do
            if not outer[x] then table.insert(displaced, x) end
        end
        table.sort(displaced)
        print(string.format("[vertical_fullwidth_border] digit_only_line_columns=%s",
            table.concat(displaced, ",")))
        assert.are.same({}, displaced,
            "larger descendant moved only its portion of the decoration line")

        -- Isolate the mutable-pen regression from border painting. FreeType's
        -- vertical glyph loop advances its y pen; the underline must retain
        -- the run's original y rather than starting one glyph too late.
        local plain_first = assert(words["甲"], "plain first character was not rendered")
        local plain_digit = assert(words["２"], "plain fullwidth digit was not rendered")
        local plain_last = assert(words["乙"], "plain last character was not rendered")
        local plain_y0 = math.min(plain_first.y, plain_digit.y, plain_last.y)
        local plain_y1 = math.max(plain_first.y + plain_first.h,
            plain_digit.y + plain_digit.h, plain_last.y + plain_last.h)
        local plain_span = plain_y1 - plain_y0
        local plain_continuous = {}
        local plain_scan_left = math.min(plain_first.x, plain_digit.x, plain_last.x)
        local plain_scan_right = math.min(Screen:getWidth() - 1,
            math.max(plain_first.x + plain_first.w,
                plain_digit.x + plain_digit.w, plain_last.x + plain_last.w) + 8)
        for x = plain_scan_left, plain_scan_right do
            local dark = 0
            for y = plain_y0, plain_y1 - 1 do
                local px = Screen.bb:getPixel(x, y)
                if px and px:getR() < 200 then dark = dark + 1 end
            end
            if dark >= plain_span * 0.8 then
                table.insert(plain_continuous, x)
            end
        end
        print(string.format("[vertical_fullwidth_border] plain_continuous_line_columns=%s",
            table.concat(plain_continuous, ",")))
        assert.is_true(#plain_continuous >= 1,
            "vertical underline used the post-glyph y pen instead of the run origin")
    end)

    it("keeps an overline aligned across the TOC's nested font sizes", function()
        if readerui then
            readerui:onClose()
            readerui = nil
        end

        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 32px; }
p { margin: 1em; }
a { color: #000000; text-decoration: overline; }
.font-090per { font-size: 90%; }
.font-140per { font-size: 140%; }
.color-01 { color: #EE7600; }
</style></head><body>
<p><a href="#"><span class="font-090per">第</span><span class="font-140per"><span class="color-01">３</span></span><span class="font-090per">章</span></a></p>
</body></html>]])
        f:close()

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local words = {}
        for x = Screen:getWidth() - 4, 4, -4 do
            for y = 4, Screen:getHeight() - 4, 4 do
                local word = readerui.document:getWordFromPosition({x=x, y=y})
                if word and word.sbox and (word.word == "第" or word.word == "３"
                        or word.word == "章") then
                    words[word.word] = word.sbox
                end
            end
        end

        local function is_rule_pixel(px)
            if not px then return false end
            -- The emulator's test buffer may be grayscale, so the authored
            -- orange (#EE7600) cannot be identified by RGB hue here.
            return px:getR() < 220
        end

        local function rule_columns(box)
            local columns = {}
            local y0 = box.y + 2
            local y1 = box.y + box.h - 3
            local span = y1 - y0 + 1
            local scan_left = math.max(0, box.x - 16)
            local scan_right = math.min(Screen:getWidth() - 1, box.x + box.w + 4)
            for x = scan_left, scan_right do
                local pixels = 0
                for y = y0, y1 do
                    if is_rule_pixel(Screen.bb:getPixel(x, y)) then
                        pixels = pixels + 1
                    end
                end
                if pixels >= span * 0.75 then
                    table.insert(columns, x)
                end
            end
            return columns
        end

        local first = assert(words["第"], "第 was not rendered")
        local digit = assert(words["３"], "３ was not rendered")
        local last = assert(words["章"], "章 was not rendered")
        local first_columns = rule_columns(first)
        local digit_columns = rule_columns(digit)
        local last_columns = rule_columns(last)
        print(string.format(
            "[vertical_fullwidth_border] toc_overline_columns 第=%s ３=%s 章=%s",
            table.concat(first_columns, ","), table.concat(digit_columns, ","),
            table.concat(last_columns, ",")))
        assert.is_true(#first_columns > 0, "overline beside 第 was not found")
        assert.is_true(#digit_columns > 0, "overline beside ３ was not found")
        assert.is_true(#last_columns > 0, "overline beside 章 was not found")
        assert.are.equal(first_columns[1], digit_columns[1],
            "larger orange descendant shifted the overline horizontally")
        assert.are.equal(first_columns[1], last_columns[1],
            "same-sized descendants did not share one overline position")
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
