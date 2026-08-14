--[[--
Vertical text: tate-chu-yoko centering and text decoration.

TCY keeps ASCII digits horizontal inside a vertical em slot. The glyph run
must be centred on the column axis, while underline/overline remains a
vertical sideline rather than following the run's horizontal baseline.
--]]

describe("Vertical TCY centering and decoration #tcy_decoration", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local html_path = "/tmp/koreader_vertical_tcy_decoration.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function fixture()
        local f = assert(io.open(html_path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 32px; line-height: 1; }
p { margin: 0 1em 0 0; }
.tcy { text-combine-upright: digits 2; color: #808080; }
.over { text-decoration: overline; }
.under { text-decoration: underline; }
</style></head><body>
<p>甲<span class="tcy">1</span>乙</p>
<p>丙<span class="tcy">10</span>丁</p>
<p>戊<span class="tcy over">30</span>己</p>
<p>庚<span class="tcy under">40</span>辛</p>
</body></html>]])
        f:close()
        return html_path
    end

    local function find_word(doc, target)
        local seen = {}
        for x = Screen:getWidth() - 3, 3, -3 do
            for y = 3, Screen:getHeight() - 3, 3 do
                local word = doc:getWordFromPosition({ x = x, y = y })
                if word and word.word == target and word.sbox then
                    local sb = word.sbox
                    local key = string.format("%d:%d:%d:%d", sb.x, sb.y, sb.w, sb.h)
                    seen[key] = { x = sb.x, y = sb.y, w = sb.w, h = sb.h }
                end
            end
        end
        local _, sb = next(seen)
        return sb
    end

    local function is_gray(x, y)
        local px = Screen.bb:getPixel(x, y)
        return px and px:getR() >= 80 and px:getR() <= 190
    end

    local function gray_bounds(sb)
        local min_x, max_x
        for y = sb.y, sb.y + sb.h - 1 do
            for x = sb.x, sb.x + sb.w - 1 do
                if is_gray(x, y) then
                    min_x = math.min(min_x or x, x)
                    max_x = math.max(max_x or x, x)
                end
            end
        end
        return assert(min_x, "no authored gray digit pixels"), max_x
    end

    before_each(function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(fixture()),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
    end)

    it("centres one- and two-digit runs on the vertical column axis", function()
        for _, target in ipairs({ "1", "10" }) do
            local sb = assert(find_word(readerui.document, target), target .. " missing")
            local min_x, max_x = gray_bounds(sb)
            local ink_center2 = min_x + max_x
            local slot_center2 = 2 * sb.x + sb.w - 1
            local drift2 = math.abs(ink_center2 - slot_center2)
            print(string.format(
                "[tcy_center] %s sbox={%d,%d,%d,%d} ink_x=%d..%d drift2=%d",
                target, sb.x, sb.y, sb.w, sb.h, min_x, max_x, drift2))
            assert.is_true(drift2 <= 4,
                target .. " is not centred on the vertical column axis")
        end
    end)

    it("draws a TCY text decoration as a vertical sideline", function()
        for _, target in ipairs({ "30", "40" }) do
            local sb = assert(find_word(readerui.document, target),
                "decorated TCY missing")
            local row_counts, column_counts = {}, {}
            local x0, x1 = math.max(0, sb.x - 8),
                math.min(Screen:getWidth() - 1, sb.x + sb.w + 8)
            local y0, y1 = math.max(0, sb.y - 4),
                math.min(Screen:getHeight() - 1, sb.y + sb.h + 4)
            for y = y0, y1 do
                for x = x0, x1 do
                    if is_gray(x, y) then
                        row_counts[y] = (row_counts[y] or 0) + 1
                        column_counts[x] = (column_counts[x] or 0) + 1
                    end
                end
            end
            local max_row, max_column = 0, 0
            for _, count in pairs(row_counts) do
                max_row = math.max(max_row, count)
            end
            for _, count in pairs(column_counts) do
                max_column = math.max(max_column, count)
            end
            print(string.format(
                "[tcy_decoration] %s max_row=%d max_column=%d slot_h=%d",
                target, max_row, max_column, sb.h))
            assert.is_true(max_column >= math.floor(sb.h * 0.7),
                "TCY vertical sideline is missing or too short")
            assert.is_true(max_column > max_row,
                "TCY text decoration was drawn horizontally")
        end
    end)

    after_each(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
    end)
end)
