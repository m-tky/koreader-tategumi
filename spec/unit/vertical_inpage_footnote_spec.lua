describe("Vertical text: in-page footnotes", function()
    local Device, Registry, ReaderUI, UIManager
    local reader, path

    setup(function()
        require("commonrequire")
        disable_plugins()
        Device = require("device")
        Registry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
    end)

    after_each(function()
        if reader then reader:onClose(); reader = nil end
        UIManager:quit()
        UIManager._exit_code = nil
        if path then os.remove(path); path = nil end
    end)

    local function open(writing_mode, note_text)
        local name = os.tmpname()
        os.remove(name)
        path = name .. ".xhtml"
        local file = assert(io.open(path, "wb"))
        file:write([[<html xmlns="http://www.w3.org/1999/xhtml" lang="ja"><head><style>
            body { writing-mode: ]], writing_mode, [[; }
            p, aside { margin: 0; }
            </style></head><body><p>本文<a href="#note" role="doc-noteref">1</a>天地玄黄</p>
            <p style="page-break-before: always">次頁</p>
            <aside id="note" role="doc-footnote"><p>]], note_text, [[</p></aside></body></html>]])
        file:close()
        reader = ReaderUI:new{ dimen = Device.screen:getSize(), document = Registry:openDocument(path) }
        UIManager:show(reader)
        reader.document:setVisiblePageCount(1)
        reader.document:setFontSize(26)
        fastforward_ui_events()
        return reader.document
    end

    local function locate(doc, text)
        local hits = doc:findAllText(text, false, 0, 100, false)
        assert.truthy(hits and hits[1], "missing fixture text: " .. text)
        return hits[1].start
    end

    local function box(doc, xp)
        local ending = assert(doc:getNextVisibleWordEnd(xp))
        local boxes = doc:getScreenBoxesFromPositions(xp, ending, true)
        return boxes and boxes[1]
    end

    local function gotoPage(page)
        reader.rolling:onGotoPage(page)
        fastforward_ui_events()
    end

    it("exposes a selectable footnote to the left of vertical body text", function()
        local doc = open("vertical-rl", "注釈の内容")
        assert.is_true(reader.styletweak:isTweakEnabled("footnote-inpage_epub"))
        local note = locate(doc, "注")
        local body = locate(doc, "本")
        local page = doc:getPageFromXPointer(body)
        assert.is_true(doc:getPageFromXPointer(note) > page)
        gotoPage(page)
        local note_box = assert(box(doc, note), "note must have an on-page box")
        local body_box = assert(box(doc, body))
        assert.is_true(note_box.x + note_box.w < body_box.x)
        local pos = { x = note_box.x + note_box.w/2, y = note_box.y + note_box.h/2 }
        local word = doc:getWordFromPosition(pos, true)
        assert.truthy(word)
        assert.equals(note, word.pos0)
        local selected = doc:getTextFromPositions(pos, pos)
        assert.equals("注", selected.text)
        assert.is_true(#selected.sboxes > 0)

        reader.styletweak:onToggleStyleTweak("footnote-inpage_epub", nil, true)
        gotoPage(doc:getPageFromXPointer(body))
        assert.is_nil(box(doc, note))
        gotoPage(doc:getPageFromXPointer(note))
        assert.truthy(box(doc, note), "disabling in-page notes keeps the original note readable")
    end)

    it("keeps a long footnote vertical on continuation pages", function()
        local doc = open("vertical-rl", ("天地玄黄宇宙洪荒"):rep(110) .. "脚注終端")
        local note_end = locate(doc, "端")
        local canonical_page = doc:getPageFromXPointer(note_end)
        local body_page = doc:getPageFromXPointer(locate(doc, "本"))
        local continuation
        for page = body_page + 1, canonical_page - 1 do
            gotoPage(page)
            if doc:getCurrentPage() == page and box(doc, note_end) then
                continuation = page
                break
            end
        end
        assert.truthy(continuation, "the final note character must be visible before its original location")
        assert.equals("vertical-rl", doc:getPageWritingMode(continuation))
        local b = assert(box(doc, note_end))
        local word = doc:getWordFromPosition({ x = b.x + b.w/2, y = b.y + b.h/2 }, true)
        assert.truthy(word)
        assert.equals(note_end, word.pos0)
    end)
end)
