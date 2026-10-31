-- Latin words must remain complete in one vertical column. Check both a
-- roomy column and a short column, without a font/margin Cartesian sweep.
describe("Vertical text: Latin word no-split #latin_split", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/latin_split_test.epub"

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
    end)

    for _, case in ipairs({
        {name = "roomy", font_size = 20, margin = 20}, -- unscaled_size_check: ignore (fixed CSS-pixel test input)
        {name = "short", font_size = 28, margin = 100}, -- unscaled_size_check: ignore (fixed CSS-pixel test input)
    }) do
        it("keeps complete Latin words in a " .. case.name .. " column", function()
            local f = assert(io.open(epub_path, "rb"), "latin_split_test.epub fixture missing")
            f:close()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
            UIManager:show(readerui)
            local doc = readerui.document
            doc:setVisiblePageCount(1)
            doc:setFontSize(case.font_size)
            doc:setPageMargins(20, case.margin, 20, case.margin)
            readerui.rolling:onUpdatePos()
            fastforward_ui_events()
            assert.is_true(doc:isVerticalText())

            for _, target in ipairs({"Nachbild", "Geschehen"}) do
                local hits = doc:findAllText(target, false, 0, 10, false)
                assert.truthy(hits and hits[1], target .. " missing from fixture")
                local hit = hits[1]
                readerui.rolling:onGotoPage(doc:getPageFromXPointer(hit.start))
                fastforward_ui_events()
                local boxes = doc:getScreenBoxesFromPositions(hit.start, hit["end"], true)
                assert.truthy(boxes and boxes[1], target .. " has no screen geometry")
                local column_x = boxes[1].x
                for _, box in ipairs(boxes) do
                    assert.is_true(box.w > 0 and box.h > 0, target .. " has an empty rectangle")
                    assert.is_true(math.abs(box.x - column_x) <= 2, target .. " split across columns")
                    local word = doc:getWordFromPosition({
                        x = box.x + math.floor(box.w / 2),
                        y = box.y + math.floor(box.h / 2),
                    })
                    assert.truthy(word, target .. " is not selectable")
                    assert.equals(target, word.word, "hit testing returned only a Latin word fragment")
                end
            end
        end)
    end
end)
