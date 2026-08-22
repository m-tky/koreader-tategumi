--[[--
Vertical table layout uses logical coordinates: columns advance on the inline
axis (top to bottom) and rows advance on the block axis (right to left).
--]]

describe("Vertical text: table logical axes #vertical_table_axes", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_table_axes.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function find_word(doc, target)
        local found
        for x = Screen:getWidth() - 3, 3, -3 do
            for y = 3, Screen:getHeight() - 3, 3 do
                local word = doc:getWordFromPosition({ x = x, y = y })
                if word and word.word == target and word.sbox then found = word.sbox end
            end
        end
        return assert(found, target .. " was not rendered")
    end

    local function widest_rule_to_right(box)
        local bb = Screen.bb
        local xs = {}
        local y0 = math.max(0, box.y - 20)
        local y1 = math.min(Screen:getHeight() - 1, box.y + box.h + 20)
        -- Ignore glyph strokes; the authored outer edge is well outside the
        -- one-glyph content box in this fixed-width cell.
        for x = box.x + box.w + 30, math.min(Screen:getWidth() - 1, box.x + box.w + 140) do
            local dark = 0
            for y = y0, y1 do
                local px = bb:getPixel(x, y)
                if px and px:getR() < 180 then dark = dark + 1 end
            end
            if dark >= box.h * 0.8 then xs[#xs + 1] = x end
        end
        local widest, run, previous = 0, 0, nil
        for _, x in ipairs(xs) do
            run = previous and x == previous + 1 and run + 1 or 1
            widest = math.max(widest, run)
            previous = x
        end
        return widest
    end

    it("maps columns to inline and rows to block progression", function()
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 28px; }
p { margin: 0; }
table { border-spacing: 0; border: 2px solid; }
td { padding-top: .5em; padding-bottom: .5em; border: 1px solid; }
</style></head><body><table><tr><td>甲</td><td>乙</td></tr><tr><td>丙</td><td>丁</td></tr></table></body></html>]])
        f:close()
        readerui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(path) }
        UIManager:show(readerui)
        fastforward_ui_events()

        local a, b = find_word(readerui.document, "甲"), find_word(readerui.document, "乙")
        local c, d = find_word(readerui.document, "丙"), find_word(readerui.document, "丁")
        assert.is_true(a.y < b.y, "second column did not advance down the inline axis")
        assert.is_true(c.y < d.y, "second column in row two did not advance down the inline axis")
        assert.is_true(c.x < a.x, "second row did not advance left on the block axis")
        assert.is_true(d.x < b.x, "second row did not advance left on the block axis")
    end)

    it("keeps colspan on the inline axis and rowspan on the block axis", function()
        if readerui then readerui:onClose(); readerui = nil end
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 24px; }
table { border-spacing: 0; margin: 0 0 1em 0; }
td { width: 3em; height: 3em; padding: 0; border: 1px solid; }
</style></head><body>
<table><tr><td colspan="2">甲</td><td>乙</td></tr>
<tr><td>丙</td><td>丁</td><td>戊</td></tr></table>
<table><tr><td rowspan="2" style="vertical-align: middle">己</td><td>庚</td></tr>
<tr><td>辛</td></tr></table>
</body></html>]])
        f:close()
        readerui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(path) }
        UIManager:show(readerui)
        fastforward_ui_events()

        local doc = readerui.document
        local jia, yi = find_word(doc, "甲"), find_word(doc, "乙")
        local bing, ding, wu = find_word(doc, "丙"), find_word(doc, "丁"), find_word(doc, "戊")
        -- A colspan of two cells consumes two inline tracks: the following
        -- cell is farther down than one ordinary cell track.
        assert.is_true(yi.y > jia.y, "colspan did not advance on the inline axis")
        assert.is_true(yi.y - jia.y > ding.y - bing.y,
            "colspan did not consume two logical inline tracks")
        assert.is_true(bing.x < jia.x and ding.x < jia.x and wu.x < jia.x,
            "second table row did not advance left on the block axis")

        local ji, geng, xin = find_word(doc, "己"), find_word(doc, "庚"), find_word(doc, "辛")
        -- A rowspan spans rows (the block axis), so its vertically centred
        -- glyph lies between the two row glyphs rather than below them.
        assert.is_true(geng.x > xin.x, "rowspan rows did not advance left on the block axis")
        assert.is_true(ji.x < geng.x and ji.x > xin.x,
            "rowspan was laid out on the inline axis instead of the block axis")
    end)

    it("maps collapsed logical table borders to vertical-rl edges", function()
        if readerui then readerui:onClose(); readerui = nil end
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 28px; }
table { border-collapse: collapse; margin: 1em; }
td { writing-mode: vertical-rl; width: 4em; height: 4em; padding: 0; border: 0; }
td { border-block-start: 6px solid; border-inline-start: 3px solid; }
</style></head><body><p>前</p><table><tr><td>甲</td></tr></table></body></html>]])
        f:close()
        readerui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(path) }
        UIManager:show(readerui)
        fastforward_ui_events()

        local box = find_word(readerui.document, "甲")
        local bb = Screen.bb
        local function dark(x, y)
            local px = bb:getPixel(x, y)
            return px and px:getR() < 180
        end
        local rules = {}
        for x = math.max(0, box.x - 160), math.min(Screen:getWidth() - 1, box.x + box.w + 160) do
            local n = 0
            for y = math.max(0, box.y - 20), math.min(Screen:getHeight() - 1, box.y + box.h + 20) do
                if dark(x, y) then n = n + 1 end
            end
            if n >= box.h * 0.8 then table.insert(rules, x) end
        end
        local right_rule = false
        for _, x in ipairs(rules) do
            if x > box.x + box.w + 8 then right_rule = true; break end
        end
        assert.is_true(right_rule, "collapsed border-block-start was not on the right edge")
    end)

    it("prefers a wider row border over a cell border", function()
        if readerui then readerui:onClose(); readerui = nil end
        local function render(cell_border)
            local f = assert(io.open(path, "wb"))
            f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 28px; }
p { margin: 0; }
table { border-collapse: collapse; margin: 1em; }
tr { border-right: 7px solid; }
td { width: 4em; height: 4em; padding: 0; ]] .. cell_border .. [[ }
</style></head><body><p>前</p><table><tr><td>甲</td></tr></table></body></html>]])
            f:close()
            readerui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(path) }
            UIManager:show(readerui)
            fastforward_ui_events()
            return widest_rule_to_right(find_word(readerui.document, "甲"))
        end

        local wider = render("border-right: 2px solid;")
        assert.is_true(wider >= 3,
            "wider row border did not win over the cell border")
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
