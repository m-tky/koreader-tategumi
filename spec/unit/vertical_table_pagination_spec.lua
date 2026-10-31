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
<tr><td rowspan="12">標</td><td>01</td></tr>]])
        for row = 2, 12 do
            f:write(string.format("<tr><td>%02d</td></tr>", row))
        end
        -- Continue past the first page; the original 20-row table fitted on
        -- one page and never exercised pagination.
        for row = 13, 59, 2 do
            f:write(string.format("<tr><td>%02d</td><td>%02d</td></tr>", row, row + 1))
        end
        f:write("</table></body></html>")
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
        doc:setVisiblePageCount(1)
        doc:setFontSize(40)
        readerui.rolling:onUpdatePos()
        fastforward_ui_events()
        local page_count = doc:getPageCount()
        assert.is_true(page_count > 1, "fixture must exercise table pagination")
        local sentinel_count = 0
        local row_counts = {}
        local content_pages = 0
        for page = 1, page_count do
            readerui.rolling:onGotoPage(page)
            fastforward_ui_events()
            local boxes = {}
            local has_labels = false
            for _, item in pairs(collect_words(doc)) do
                boxes[#boxes + 1] = item.sbox
                if item.text == "標" then
                    sentinel_count = sentinel_count + 1
                elseif item.text:match("^%d%d$") then
                    row_counts[item.text] = (row_counts[item.text] or 0) + 1
                    has_labels = true
                end
            end
            if has_labels then content_pages = content_pages + 1 end
            -- Distinct table words must not occupy the same rectangle.
            -- Ignore tiny edge contact from glyph metrics.
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
        assert.is_true(content_pages >= 2, "table labels must occupy at least two pages")
        assert.are.equal(1, sentinel_count, "rowspan word must appear on exactly one page")
        for row = 1, 60 do
            local text = string.format("%02d", row)
            assert.are.equal(1, row_counts[text], text .. " must appear exactly once")
        end
    end)

    teardown(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
        os.remove(path)
    end)
end)
