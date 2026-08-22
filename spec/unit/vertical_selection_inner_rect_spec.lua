-- Regression coverage for selection rectangles in vertical-rl documents.
--
-- The deliberately asymmetric padding and border make stale physical-axis
-- corrections visible: the word box returned by crengine and the rectangle
-- used by the selection/highlight UI must describe the same glyph.

describe("Vertical text: selection inner rectangles #vertical_selection_inner_rect", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager, Geom
    local readerui
    local path = "/tmp/koreader_vertical_selection_inner_rect.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        Geom = require("ui/geometry")
    end)

    local function open_document(legacy)
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; }
body { writing-mode: vertical-rl; font-size: 28px; line-height: 1;
       padding: 13px 37px 29px 61px;
       border-style: solid; border-width: 2px 7px 3px 11px; }
p { margin: 0; }
</style></head><body><p>選択矩形の内側補正を確認するための縦書き本文です。選択矩形の内側補正を確認するための縦書き本文です。</p></body></html>]])
        f:close()
        local document = DocumentRegistry:openDocument(path)
        if legacy then
            -- INNER_FIELDS_SET belongs to enhanced block rendering.  Force the
            -- legacy selection/hit-test correction path for this regression.
            document:setBlockRenderingFlags(0)
        end
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = document,
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()
        return readerui.document
    end

    local function find_word(doc)
        for x = Screen:getWidth() - 10, 10, -5 do
            for y = 10, Screen:getHeight() - 10, 5 do
                local word = doc:getWordFromPosition(Geom:new{x = x, y = y})
                if word and word.word and word.word ~= "" and word.sbox
                        and word.sbox.w > 0 and word.sbox.h > 0 then
                    return word
                end
            end
        end
    end

    local function center(box)
        return box.x + math.floor(box.w / 2), box.y + math.floor(box.h / 2)
    end

    it("keeps a word xpointer selection rectangle on the glyph inner box", function()
        local doc = open_document(true)
        assert.is_true(doc:isVerticalText())
        local word = assert(find_word(doc), "no word found in asymmetric vertical fixture")
        local x, y = center(word.sbox)
        local ok, selected = pcall(function()
            return doc:getTextFromPositions({x = x, y = y}, {x = x, y = y})
        end)
        assert.is_true(ok, "getTextFromPositions failed")
        local sb = selected and selected.sboxes and selected.sboxes[1]
        assert.truthy(sb, "word xpointer returned no selection rectangle")
        local sx, sy = center(sb)
        assert.is_true(math.abs(sx - x) <= 2,
            string.format("selection x-center drifted by %dpx", sx - x))
        assert.is_true(math.abs(sy - y) <= 2,
            string.format("selection y-center drifted by %dpx", sy - y))
    end)

    it("draws a hold highlight over the same inner rectangle", function()
        local doc = open_document(true)
        local word = assert(find_word(doc), "no word found in asymmetric vertical fixture")
        local x, y = center(word.sbox)
        readerui.highlight:onHold(nil, {pos = Geom:new{x = x, y = y}})
        fastforward_ui_events()
        local displayed
        for _, sboxes in pairs(readerui.view.highlight.temp or {}) do
            if sboxes and #sboxes > 0 then displayed = sboxes[1]; break end
        end
        assert.truthy(displayed, "hold did not produce a highlight rectangle")
        local dx, dy = center(displayed)
        local wx, wy = center(word.sbox)
        assert.is_true(math.abs(dx - wx) <= 2,
            string.format("highlight x-center drifted by %dpx", dx - wx))
        assert.is_true(math.abs(dy - wy) <= 2,
            string.format("highlight y-center drifted by %dpx", dy - wy))
    end)

    after_each(function()
        if readerui then readerui:onClose(); readerui = nil end
        UIManager:quit()
    end)
end)
