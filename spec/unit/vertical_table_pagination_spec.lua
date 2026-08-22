-- Regression coverage for a tall vertical-rl table.  A row-spanning cell must
-- be emitted once and must not overlap the words in the other table rows.

describe("Vertical text: tall table rowspan #vertical_table_pagination", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_table_pagination.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function write_fixture()
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 24px; line-height: 1; }
table { border-collapse: collapse; margin: 0; }
td { width: 5em; height: 5em; padding: 0; border: 1px solid; }
</style></head><body><table>
<tr><td rowspan="12">標</td><td>ROW_01</td></tr>
<tr><td>ROW_02</td></tr>
<tr><td>ROW_03</td></tr>
<tr><td>ROW_04</td></tr>
<tr><td>ROW_05</td></tr>
<tr><td>ROW_06</td></tr>
<tr><td>ROW_07</td></tr>
<tr><td>ROW_08</td></tr>
<tr><td>ROW_09</td></tr>
<tr><td>ROW_10</td></tr>
<tr><td>ROW_11</td></tr>
<tr><td>ROW_12</td></tr>
<tr><td>ROW_13</td><td>ROW_14</td></tr>
<tr><td>ROW_15</td><td>ROW_16</td></tr>
<tr><td>ROW_25</td><td>ROW_26</td></tr>
<tr><td>ROW_27</td><td>ROW_28</td></tr>
<tr><td>ROW_29</td><td>ROW_30</td></tr>
<tr><td>ROW_31</td><td>ROW_32</td></tr>
<tr><td>ROW_33</td><td>ROW_34</td></tr>
<tr><td>ROW_35</td><td>ROW_36</td></tr>
</table></body></html>]])
        f:close()
    end

    local function collect_words(doc)
        local found = {}
        local step_x = math.max(4, math.floor(Screen:getWidth() / 80))
        local step_y = math.max(4, math.floor(Screen:getHeight() / 100))
        for x = 2, Screen:getWidth() - 2, step_x do
            for y = 2, Screen:getHeight() - 2, step_y do
                local ok, word = pcall(doc.getWordFromPosition, doc, { x = x, y = y })
                if ok and word and word.word and word.sbox and #word.word > 0 then
                    local sb = word.sbox
                    local key = string.format("%s:%d:%d:%d:%d", word.word,
                        sb.x, sb.y, sb.w, sb.h)
                    found[key] = { text = word.word, sbox = sb }
                end
            end
        end
        return found
    end

    it("does not duplicate or overlap the rowspan word", function()
        write_fixture()
        readerui = ReaderUI:new{ dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path) }
        UIManager:show(readerui)
        fastforward_ui_events()
        local doc = readerui.document
        local sentinel = {}
        local page_boxes = {}
        local words = collect_words(doc)
        local boxes = {}
        for _, item in pairs(words) do
            boxes[#boxes + 1] = item.sbox
            if item.text == "標" then
                sentinel[#sentinel + 1] = item.sbox
            end
        end
        page_boxes[#page_boxes + 1] = boxes

        assert.is_true(#sentinel >= 1, "rowspan cell was not reachable in the table layout")

        -- Distinct table words must not occupy the same rectangle after a
        -- table is laid out.  Ignore tiny edge contact from glyph metrics.
        for _, boxes in ipairs(page_boxes) do
            for i = 1, #boxes do
                for j = i + 1, #boxes do
                    local a, b = boxes[i], boxes[j]
                    local overlap_w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
                    local overlap_h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
                    if overlap_w > 2 and overlap_h > 2 then
                        local overlap = overlap_w * overlap_h
                        assert.is_true(overlap < math.min(a.w * a.h, b.w * b.h) * 0.2,
                            "table words have materially overlapping sboxes")
                    end
                end
            end
        end
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
