describe("Vertical text writing-mode API #vertical_writing_mode_api", function()
    local Registry, ReaderUI, Screen, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        Registry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function open_html(body)
        local path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        finally(function() os.remove(path) end)
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
            html, body { margin: 0; padding: 0; }
            p { margin: 0; text-align: left; }
            </style></head><body>]], body, [[</body></html>]])
        f:close()
        local reader = ReaderUI:new{dimen = Screen:getSize(), document = Registry:openDocument(path)}
        local closed = false
        local function close()
            if closed then return end
            closed = true
            reader:onClose()
            UIManager:quit()
            UIManager._exit_code = nil
        end
        finally(close)
        UIManager:show(reader)
        reader.document:setVisiblePageCount(1)
        reader.document:setFontSize(26)
        fastforward_ui_events()
        return reader, close
    end

    local function locate(reader, text, mode)
        local hits = reader.document:findAllText(text, false, 0, 100, false)
        assert.truthy(hits and hits[1], "missing text: " .. text)
        for _, hit in ipairs(hits) do
            local xp = hit.start
            local page = reader.document:getPageFromXPointer(xp)
            -- A writing-mode transition can share a page with its predecessor.
            -- Exercise a page stamped with the requested mode, not that boundary.
            if not mode or reader.document:getPageWritingMode(page) == mode then
                reader.rolling:onGotoPage(page)
                fastforward_ui_events()
                return xp, page
            end
        end
        error("no page with writing mode " .. tostring(mode))
    end

    it("separates book progression from the current page's geometry", function()
        local reader = open_html(
            '<div style="writing-mode: horizontal-tb"><p>' .. ("横書きの本文です。"):rep(100) .. '</p></div>' ..
            '<div style="writing-mode: vertical-rl; page-break-before: always"><p>' .. ("縦書きの本文です。"):rep(100) .. '</p></div>')
        local doc = reader.document
        assert.is_true(doc:hasVerticalContent())
        for _, sample in ipairs({{"横書き", "horizontal-tb"}, {"縦書き", "vertical-rl"}}) do
            local xp, page = locate(reader, sample[1], sample[2])
            assert.equals(sample[2], doc:getPageWritingMode(page))
            assert.equals(sample[2], doc:getPageWritingMode(), string.format("target=%d current=%d visible=%d", page,
                doc:getCurrentPage(true), doc:getVisiblePageCount()))
            assert.equals(sample[2] == "vertical-rl", doc:isVerticalPage())
            assert.is_true(reader.view:shouldInvertPageProgression(), "book progression must not change with the page")
            local doc_y, doc_x = doc:getPosFromXPointer(xp)
            local screen_x, screen_y = doc._document:docToScreenPoint(doc_y, doc_x)
            local y, x = doc:getScreenPositionFromXPointer(xp)
            assert.equals(screen_x, x)
            assert.equals(screen_y, y)
            local pos = {x = x + 2, y = y + 2}
            assert.equals(sample[2] == "vertical-rl", doc:isVerticalAtPosition(pos))
            local word = doc:getWordFromPosition(pos)
            assert.truthy(word and word.word and word.word:find(sample[1]:sub(1, 3), 1, true),
                "word selection must follow the target page's axes: " .. tostring(word and word.word))
        end
        doc:setVisiblePageCount(2)
        assert.equals(2, doc:getVisiblePageCount())
        local boundary
        for page = 1, doc:getPageCount(true) - 1 do
            if not doc:isVerticalPage(page) and doc:isVerticalPage(page + 1) then
                boundary = page
                break
            end
        end
        assert.truthy(boundary, "fixture must provide a mixed-mode spread")
        -- Deliberately start at the transition even if its parity is unusual.
        doc:gotoPage(boundary, true)
        assert.is_false(doc:isVerticalPage())
        reader.view.highlight.note_mark = "sideline"
        reader.view:setupNoteMarkPosition()
        for offset, sample in ipairs({"横書き", "縦書き"}) do
            local xp
            for _, hit in ipairs(doc:findAllText(sample, false, 0, 100, false)) do
                if doc:getPageFromXPointer(hit.start) == boundary + offset - 1 then
                    xp = hit.start
                    break
                end
            end
            assert.truthy(xp, "missing text on spread page " .. offset)
            local y, x = doc:getScreenPositionFromXPointer(xp)
            local pos = {x = x + 2, y = y + 2}
            assert.equals(offset == 2, doc:isVerticalAtPosition(pos))
            local word = doc:getWordFromPosition(pos)
            assert.truthy(word and word.word:find(sample:sub(1, 3), 1, true))
            local painted = {}
            local bb = {paintRect = function(_, px, py, w, h)
                painted[#painted + 1] = {x = px, y = py, w = w, h = h}
            end}
            reader.view:drawHighlightRect(bb, 0, 0, word.sbox, "underscore", nil, true)
            assert.equals(2, #painted, "underline and note marker must both be drawn")
            if offset == 2 then
                assert.equals(word.sbox.h, painted[1].h, "vertical sideline must span the column height")
                assert.equals(reader.view.note_mark_pos_y1, painted[2].y)
            else
                assert.equals(word.sbox.w, painted[1].w, "horizontal underline must span the word width")
                assert.equals(reader.view.note_mark_pos_x1, painted[2].x)
            end
        end
        reader.styletweak.book_style_tweak = "body, div { writing-mode: horizontal-tb !important; }"
        reader.styletweak.book_style_tweak_enabled = true
        reader.styletweak:updateCssText(true)
        fastforward_ui_events()
        assert.is_false(doc:hasVerticalContent(), "content query must follow rerendering")
        assert.equals("horizontal-tb", doc:getPageWritingMode(), "page query must not retain a cached vertical result")
    end)

    it("treats vertical-lr as the documented vertical-rl compatibility alias", function()
        local positions = {}
        for _, mode in ipairs({"vertical-rl", "vertical-lr"}) do
            local reader, close = open_html('<div style="writing-mode: ' .. mode .. '"><p>天地玄黄宇宙洪荒</p></div>')
            local xp = locate(reader, "天地")
            assert.equals("vertical-rl", reader.document:getPageWritingMode())
            local y, x = reader.document:getScreenPositionFromXPointer(xp)
            positions[#positions + 1] = {x = x, y = y}
            close()
        end
        assert.same(positions[1], positions[2])
    end)
end)
