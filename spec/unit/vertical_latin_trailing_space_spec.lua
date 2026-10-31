-- A Latin phrase wrapping at its space must leave both words selectable in
-- reading order. The trim counter also confirms this fixture exercises the
-- rendered-string trim, which selection geometry alone cannot observe.
describe("Vertical text: Latin trailing space trim #latin_trailing_space", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui, path

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    after_each(function()
        if readerui then readerui:onClose(); readerui = nil end
        UIManager:quit()
        if path then os.remove(path) end
    end)

    it("keeps a wrapped Latin phrase intact while trimming its line-ending space", function()
        path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja"><head><style>
html, body { margin: 0; padding: 0; writing-mode: vertical-rl; }
p { margin: 0; text-align: justify; }
</style></head><body><p>]],
            ("これは『blessing software』の完成を確認する本文です。"):rep(12),
            [[</p></body></html>]])
        f:close()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        local doc = readerui.document
        doc._document:resetVertTrailingSpaceTrim()
        doc:setFontFace("Noto Sans CJK SC")
        doc:setFontSize(24)
        doc:setVisiblePageCount(1)
        doc:setPageMargins(20, 100, 20, 100)
        readerui.rolling:onUpdatePos()
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()
        assert.is_true(doc:isVerticalText())
        local count, chars = doc._document:getVertTrailingSpaceTrim()
        assert.is_true(count > 0, "fixture must exercise line-ending Latin space trim")
        assert.is_true(chars >= count, "each trim must remove at least one space")

        local hits = doc:findAllText("blessing software", false, 0, 100, false)
        assert.truthy(hits and hits[1], "Latin phrase is missing")
        local wrapped
        for _, hit in ipairs(hits) do
            if doc:getPageFromXPointer(hit.start) == 1 and doc:getPageFromXPointer(hit["end"]) == 1 then
                local boxes = doc:getScreenBoxesFromPositions(hit.start, hit["end"], true)
                if boxes and #boxes >= 2 and boxes[1].x > boxes[#boxes].x then
                    wrapped = boxes
                    break
                end
            end
        end
        assert.truthy(wrapped, "fixture must wrap a Latin phrase between columns on page 1")
        local first, last = wrapped[1], wrapped[#wrapped]
        local start_pos = {x = first.x + math.floor(first.w / 2), y = first.y + math.floor(first.h / 2)}
        local end_pos = {x = last.x + math.floor(last.w / 2), y = last.y + math.floor(last.h / 2)}
        local before = assert(doc:getWordFromPosition(start_pos), "line-ending Latin word is not selectable")
        local after = assert(doc:getWordFromPosition(end_pos), "next-column Latin word is not selectable")
        assert.equals("blessing", before.word)
        assert.equals("software", after.word)
        -- Use the full word ranges returned by hit testing, not character
        -- positions inside the rotated words.
        local selected = doc:getTextFromXPointers(before.pos0, after.pos1)
        assert.equals("blessing software", selected, "wrapped phrase must remain complete and in reading order")
    end)
end)
