describe("Vertical text D-pad selection", function()
    local VerticalSelection = require("apps/reader/modules/readerkeyselection_vert")

    local function fixture()
        -- Logical order runs down each column, then right-to-left. The middle
        -- column is short, so repeated column moves must retain the original Y.
        local boxes = {
            { x = 100, y = 10, w = 20, h = 20 },
            { x = 100, y = 50, w = 20, h = 20 },
            { x = 100, y = 90, w = 20, h = 20 },
            { x = 60, y = 10, w = 20, h = 20 },
            { x = 20, y = 10, w = 20, h = 20 },
            { x = 20, y = 50, w = 20, h = 20 },
            { x = 20, y = 90, w = 20, h = 20 },
        }
        local doc = {}
        function doc:isVerticalAtPosition() return true end
        function doc:isXPointerInCurrentPage(xp) return boxes[xp] ~= nil end
        function doc:getNextVisibleWordStart(xp) return xp + 1 end
        function doc:getPrevVisibleWordStart(xp) return xp - 1 end
        function doc:getNextVisibleWordEnd(xp) return xp end
        function doc:getScreenBoxesFromPositions(xp) return { boxes[xp] } end
        function doc:getTextFromXPointers(xp) return tostring(xp) end
        local selector = {
            ui = { document = doc },
            view = { visible_area = { w = 600, h = 800 } },
            -- UI mirroring must not affect physical vertical-text navigation.
            mirroredUI = true,
            invert_ui_layout = true,
        }
        function selector:_setIndicatorRect(rect) self._current_indicator_pos = rect end
        local function place(xp)
            selector._previous_indicator_word = {
                pos0 = xp, pos1 = xp, sbox = boxes[xp], segments = { boxes[xp] },
            }
            local box = boxes[xp]
            local rect = { x = box.x + 8, y = box.y + 8, w = 4, h = 4 }
            function rect:copy()
                return setmetatable({ x = self.x, y = self.y, w = self.w, h = self.h }, { __index = self })
            end
            selector._current_indicator_pos = rect
        end
        place(2)
        return selector, place, boxes
    end

    local function paginatedFixture()
        local selector, place, boxes = fixture()
        local doc = selector.ui.document
        local page = 1
        for i = 1, 7 do
            local b = boxes[i]
            boxes[i + 7] = { x = b.x, y = b.y, w = b.w, h = b.h }
        end
        function doc:getCurrentPage() return page end
        function doc:getPageCount() return 2 end
        function doc:getPageFromXPointer(xp) return xp <= 7 and 1 or 2 end
        function doc:isXPointerInCurrentPage(xp)
            return boxes[xp] ~= nil and self:getPageFromXPointer(xp) == page
        end
        function doc:getNextVisibleWordStart(xp) if xp < 14 then return xp + 1 end end
        function doc:getPrevVisibleWordStart(xp) if xp > 1 then return xp - 1 end end
        function doc:getXPointer() return page == 1 and 1 or 8 end
        selector.view.view_mode = "page"
        selector.ui.rolling = { _gotoPage = function(_, target) page = target end }
        selector.clearOverlay = spy.new(function() end)
        return selector, place
    end

    it("moves down and up in logical order independently of UI mirroring", function()
        local s = fixture()
        assert.is_true(VerticalSelection.move(s, 0, 1))
        assert.equals(3, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, 0, -1)
        assert.equals(2, s._previous_indicator_word.pos0)
    end)

    it("wraps down to the next column and up to the preceding column", function()
        local s, place = fixture()
        place(3)
        VerticalSelection.move(s, 0, 1)
        assert.equals(4, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, 0, -1)
        assert.equals(3, s._previous_indicator_word.pos0)
    end)

    it("retains height through a short column in both directions", function()
        local s = fixture()
        VerticalSelection.move(s, -1, 0)
        assert.equals(4, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, -1, 0)
        assert.equals(6, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, 1, 0)
        VerticalSelection.move(s, 1, 0)
        assert.equals(2, s._previous_indicator_word.pos0)
    end)

    it("limits column lookup to the current and adjacent columns", function()
        local s, _, boxes = fixture()
        -- Unrelated columns must not increase lookup work, even on a dense page.
        for i = 8, 307 do
            boxes[i] = { x = -20 - math.floor((i - 8) / 3) * 40,
                y = 10 + ((i - 8) % 3) * 40, w = 20, h = 20 }
        end
        local doc = s.ui.document
        local geometry = spy.on(doc, "getScreenBoxesFromPositions")
        local text = spy.on(doc, "getTextFromXPointers")
        local previous = spy.on(doc, "getPrevVisibleWordStart")
        VerticalSelection.move(s, -1, 0)
        assert.equals(4, s._previous_indicator_word.pos0)
        -- Remaining current-column word, target-column word, then one word
        -- detecting the next column. Only the selected word needs its text.
        assert.spy(geometry).was_called(3)
        assert.spy(text).was_called(1)
        assert.spy(previous).was_not_called()
    end)

    it("scans only backward when moving to the right", function()
        local s, place = fixture()
        place(6)
        local doc = s.ui.document
        local forward = spy.on(doc, "getNextVisibleWordStart")
        local geometry = spy.on(doc, "getScreenBoxesFromPositions")
        VerticalSelection.move(s, 1, 0)
        assert.equals(4, s._previous_indicator_word.pos0)
        assert.spy(forward).was_not_called()
        assert.spy(geometry).was_called(3)
    end)

    it("resets the retained height after moving within a column", function()
        local s = fixture()
        VerticalSelection.move(s, -1, 0)
        VerticalSelection.move(s, 0, 1)
        VerticalSelection.move(s, 1, 0)
        assert.equals(4, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, 1, 0)
        assert.equals(1, s._previous_indicator_word.pos0)
    end)

    it("stops without selecting off-page text when no page turn is available", function()
        local s, place = fixture()
        place(7)
        VerticalSelection.move(s, 0, 1)
        assert.equals(7, s._previous_indicator_word.pos0)
        assert.equals(1, s._edge_dy)
        VerticalSelection.move(s, -1, 0)
        assert.equals(7, s._previous_indicator_word.pos0)
        assert.equals(-1, s._edge_dx)
        place(1)
        VerticalSelection.move(s, 0, -1)
        assert.equals(1, s._previous_indicator_word.pos0)
    end)

    it("moves up/down by four logical steps including column wraps", function()
        local s, place = fixture()
        place(1)
        VerticalSelection.move(s, 0, 1, true)
        assert.equals(5, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, 0, -1, true)
        assert.equals(1, s._previous_indicator_word.pos0)
    end)

    it("stops quick column movement when no page turn is available", function()
        local s = fixture()
        VerticalSelection.move(s, -1, 0, true)
        assert.equals(6, s._previous_indicator_word.pos0)
    end)

    it("leaves horizontal text to the existing selector", function()
        local s = fixture()
        s._vertical_selection_anchor_y = 60
        function s.ui.document:isVerticalAtPosition() return false end
        assert.is_false(VerticalSelection.move(s, -1, 0))
        assert.equals(2, s._previous_indicator_word.pos0)
        assert.is_nil(s._vertical_selection_anchor_y)
    end)

    it("crosses pages down and up in logical order", function()
        local s, place = paginatedFixture()
        place(7)
        VerticalSelection.move(s, 0, 1)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(8, s._previous_indicator_word.pos0)
        assert.equals(8, s.ui.rolling.xpointer)
        VerticalSelection.move(s, 0, -1)
        assert.equals(1, s.ui.document:getCurrentPage())
        assert.equals(7, s._previous_indicator_word.pos0)
        assert.spy(s.clearOverlay).was_called(2)
    end)

    it("crosses column boundaries at the retained height in both directions", function()
        local s, place = paginatedFixture()
        place(6)
        VerticalSelection.move(s, -1, 0)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(9, s._previous_indicator_word.pos0)
        assert.equals(60, s._vertical_selection_anchor_y)
        VerticalSelection.move(s, 1, 0)
        assert.equals(1, s.ui.document:getCurrentPage())
        assert.equals(6, s._previous_indicator_word.pos0)
    end)

    it("does not rescan the old page or enumerate the new page when crossing", function()
        local s, place = paginatedFixture()
        place(6)
        local geometry = spy.on(s.ui.document, "getScreenBoxesFromPositions")
        local text = spy.on(s.ui.document, "getTextFromXPointers")
        VerticalSelection.move(s, -1, 0)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(9, s._previous_indicator_word.pos0)
        -- One remaining word on the old page, the three entry-column words,
        -- and one word detecting the following column.
        assert.spy(geometry).was_called(5)
        assert.spy(text).was_called(1)
    end)

    it("retains height across a short page-entry column", function()
        local s, place = paginatedFixture()
        place(6)
        local doc = s.ui.document
        local original = doc.getScreenBoxesFromPositions
        function doc:getScreenBoxesFromPositions(xp)
            if xp == 9 or xp == 10 then return { { x = 100, y = 10, w = 20, h = 20 } } end
            return original(self, xp)
        end
        VerticalSelection.move(s, -1, 0)
        assert.equals(2, doc:getCurrentPage())
        assert.equals(20, s._current_indicator_pos.y + 2)
        VerticalSelection.move(s, -1, 0)
        VerticalSelection.move(s, -1, 0)
        assert.equals(13, s._previous_indicator_word.pos0)
    end)

    it("stops at the book boundaries in all four directions", function()
        local s, place = paginatedFixture()
        place(1)
        VerticalSelection.move(s, 0, -1)
        VerticalSelection.move(s, 1, 0)
        assert.equals(1, s.ui.document:getCurrentPage())
        assert.equals(1, s._previous_indicator_word.pos0)
        s.ui.rolling:_gotoPage(2)
        place(14)
        VerticalSelection.move(s, 0, 1)
        VerticalSelection.move(s, -1, 0)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(14, s._previous_indicator_word.pos0)
    end)

    it("takes four logical steps across pages in either direction", function()
        local s, place = paginatedFixture()
        place(7)
        VerticalSelection.move(s, 0, 1, true)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(11, s._previous_indicator_word.pos0)
        VerticalSelection.move(s, 0, -1, true)
        assert.equals(1, s.ui.document:getCurrentPage())
        assert.equals(7, s._previous_indicator_word.pos0)
    end)

    it("crosses pages during a viewport-based column jump while retaining height", function()
        local s, place = paginatedFixture()
        place(6)
        VerticalSelection.move(s, -1, 0, true)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(9, s._previous_indicator_word.pos0)
        assert.equals(60, s._vertical_selection_anchor_y)
        VerticalSelection.move(s, 1, 0, true)
        assert.equals(1, s.ui.document:getCurrentPage())
        assert.equals(6, s._previous_indicator_word.pos0)
        assert.equals(60, s._vertical_selection_anchor_y)
    end)

    it("scales quick column movement with viewport width and column spacing", function()
        for _, case in ipairs({ {600, 20}, {300, 20}, {600, 40}, {300, 40} }) do
            local width, spacing = unpack(case)
            local s, place, boxes = fixture()
            s.view.visible_area.w = width
            for i = 1, 30 do
                boxes[i] = { x = width - 20 - (i - 1) * spacing, y = 50, w = 10, h = 20 }
            end
            place(1)
            VerticalSelection.move(s, -1, 0, true)
            assert.equals(1 + math.ceil(width / 5 / spacing), s._previous_indicator_word.pos0)
            VerticalSelection.move(s, 1, 0, true)
            assert.equals(1, s._previous_indicator_word.pos0)
        end
    end)

    it("stops quick movement at the book boundaries", function()
        local s, place = paginatedFixture()
        place(1)
        VerticalSelection.move(s, 0, -1, true)
        VerticalSelection.move(s, 1, 0, true)
        assert.equals(1, s.ui.document:getCurrentPage())
        assert.equals(1, s._previous_indicator_word.pos0)
        s.ui.rolling:_gotoPage(2)
        place(14)
        VerticalSelection.move(s, 0, 1, true)
        VerticalSelection.move(s, -1, 0, true)
        assert.equals(2, s.ui.document:getCurrentPage())
        assert.equals(14, s._previous_indicator_word.pos0)
    end)

    it("extends an active hold once to the final quick-move endpoint", function()
        local s, place = paginatedFixture()
        place(7)
        s._start_indicator_highlight = true
        s.ui.highlight = { onHoldPan = spy.new(function() end) }
        function s:_createHighlightGesture(kind) return { kind = kind } end
        VerticalSelection.move(s, 0, 1, true)
        assert.equals(11, s._previous_indicator_word.pos0)
        assert.is_true(s._start_indicator_highlight)
        assert.spy(s.ui.highlight.onHoldPan).was_called(1)
    end)

    it("preserves an active hold when crossing pages", function()
        local s, place = paginatedFixture()
        place(7)
        s._start_indicator_highlight = true
        s.ui.highlight = { onHoldPan = spy.new(function() end) }
        function s:_createHighlightGesture(kind) return { kind = kind } end
        VerticalSelection.move(s, 0, 1)
        assert.is_true(s._start_indicator_highlight)
        assert.spy(s.ui.highlight.onHoldPan).was_called(1)
    end)

    it("does not reverse direction when the engine returns no next pointer", function()
        local s = fixture()
        function s.ui.document:getNextVisibleWordStart() return nil end
        VerticalSelection.move(s, 0, 1)
        assert.equals(2, s._previous_indicator_word.pos0)
    end)

    it("updates an active highlight after moving", function()
        local s = fixture()
        s._start_indicator_highlight = true
        s.ui.highlight = { onHoldPan = spy.new(function() end) }
        function s:_createHighlightGesture(kind) return { kind = kind } end
        VerticalSelection.move(s, 0, 1)
        assert.spy(s.ui.highlight.onHoldPan).was_called(1)
    end)

    it("navigates actual vertical CRE columns through the reader key handler", function()
        require("commonrequire")
        disable_plugins()
        local Device = require("device")
        require("document/canvascontext"):init(Device)
        local Registry = require("document/documentregistry")
        local ReaderUI = require("apps/reader/readerui")
        local Geom = require("ui/geometry")
        local UIManager = require("ui/uimanager")
        local path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        finally(function() os.remove(path) end)
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
            body { writing-mode: vertical-rl; margin: 0; }
            p { margin: 0; }
            </style></head><body><p>天地玄黄宇宙洪荒<br/>日月盈昃<br/>辰宿列張寒来暑往</p>
            <p style="page-break-before: always">食物栄養健康生活<br/>春夏秋冬<br/>山川草木花鳥風月</p>
            </body></html>]])
        f:close()
        local reader = ReaderUI:new{ dimen = Device.screen:getSize(), document = Registry:openDocument(path) }
        finally(function()
            reader:onClose()
            UIManager:quit()
            UIManager._exit_code = nil
        end)
        UIManager:show(reader)
        reader.document:setVisiblePageCount(1)
        reader.document:setFontSize(26)
        fastforward_ui_events()
        local doc = reader.document
        local hits = doc:findAllText("玄", false, 0, 100, false)
        assert.truthy(hits and hits[1])
        reader.rolling:onGotoPage(doc:getPageFromXPointer(hits[1].start))
        fastforward_ui_events()
        local y, x = doc:getScreenPositionFromXPointer(hits[1].start)
        local word = doc:getWordFromPosition({ x = x + 2, y = y + 2 }, true)
        assert.truthy(word and word.sbox)
        local box = word.sbox
        local selector = reader.keyselection
        selector:_beginIndicator(Geom:new{ x = box.x + box.w / 2 - 2, y = box.y + box.h / 2 - 2,
            w = 4, h = 4 }, Device.screen:getSize())
        selector._previous_indicator_word = word
        local initial = selector._current_indicator_pos:copy()
        assert.is_true(doc:isVerticalAtPosition(initial))
        selector:moveHighlightIndicator({ 0, 1 })
        assert.is_true(selector._current_indicator_pos.y > initial.y)
        assert.near(initial.x, selector._current_indicator_pos.x, 2)
        selector:moveHighlightIndicator({ 0, -1 })
        assert.near(initial.y, selector._current_indicator_pos.y, 2)
        selector:moveHighlightIndicator({ -1, 0 })
        assert.is_true(selector._current_indicator_pos.x < initial.x)
        selector:moveHighlightIndicator({ 1, 0 })
        assert.near(initial.x, selector._current_indicator_pos.x, 2)
        assert.near(initial.y, selector._current_indicator_pos.y, 2)

        local second = doc:findAllText("食", false, 0, 100, false)[1].start
        local last = doc:getPrevVisibleWordStart(second)
        local first_page, second_page = doc:getPageFromXPointer(last), doc:getPageFromXPointer(second)
        assert.is_true(second_page > first_page)
        local function place(xp)
            reader.rolling:_gotoPage(doc:getPageFromXPointer(xp))
            selector:clearOverlay()
            local ending = doc:getNextVisibleWordEnd(xp)
            local boxes = doc:getScreenBoxesFromPositions(xp, ending, true)
            assert.truthy(boxes and boxes[1])
            selector._previous_indicator_word = { pos0 = xp, pos1 = ending, sbox = boxes[1], segments = boxes }
            local b = boxes[1]
            selector:_setIndicatorRect(Geom:new{ x = b.x + b.w / 2 - 2, y = b.y + b.h / 2 - 2, w = 4, h = 4 })
            selector._edge_dx, selector._edge_dy = nil, nil
            selector._vertical_selection_anchor_y = nil
        end
        place(last)
        selector:moveHighlightIndicator({ 0, 1 })
        assert.equals(second_page, doc:getCurrentPage())
        assert.equals(second, selector._previous_indicator_word.pos0)
        selector:moveHighlightIndicator({ 0, -1 })
        assert.equals(first_page, doc:getCurrentPage())
        assert.equals(last, selector._previous_indicator_word.pos0)
        local original_y = selector._current_indicator_pos.y
        selector:moveHighlightIndicator({ -1, 0 })
        assert.equals(second_page, doc:getCurrentPage())
        selector:moveHighlightIndicator({ 1, 0 })
        assert.equals(first_page, doc:getCurrentPage())
        assert.near(original_y, selector._current_indicator_pos.y, 2)

        -- The selection anchor must remain on the original page even though
        -- its old screen coordinates now refer to text on the next page.
        place(last)
        selector:highlightPress(true)
        local anchor = reader.highlight.selected_text_start_xpointer
        assert.truthy(anchor)
        selector:moveHighlightIndicator({ 0, 1 })
        assert.equals(second_page, doc:getCurrentPage())
        assert.equals(anchor, reader.highlight.selected_text.pos0)
        assert.is_true(reader.highlight.selected_text.text:find("食", 1, true) ~= nil)
        assert.equals(1, doc:compareXPointers(anchor, reader.highlight.selected_text.pos1))

        reader.highlight:clear()
        selector._start_indicator_highlight = nil
        place(second)
        selector:highlightPress(true)
        local original_end = reader.highlight.selected_text_start_word_end_xpointer
        selector:moveHighlightIndicator({ 0, -1 })
        assert.equals(first_page, doc:getCurrentPage())
        assert.equals(original_end, reader.highlight.selected_text.pos1)
        assert.is_true(reader.highlight.selected_text.text:find("食", 1, true) ~= nil)
        assert.equals(1, doc:compareXPointers(reader.highlight.selected_text.pos0, second))

        reader.highlight:clear()
        selector._start_indicator_highlight = nil
        place(last)
        selector:highlightPress(true)
        anchor = reader.highlight.selected_text_start_xpointer
        local expected = last
        for _ = 1, 4 do expected = doc:getNextVisibleWordStart(expected) end
        selector:moveHighlightIndicator({ 0, 1, true })
        assert.equals(second_page, doc:getCurrentPage())
        assert.equals(expected, selector._previous_indicator_word.pos0)
        assert.equals(anchor, reader.highlight.selected_text.pos0)
        assert.is_true(reader.highlight.selected_text.text:find("食", 1, true) ~= nil)
        selector:moveHighlightIndicator({ 0, -1, true })
        assert.equals(first_page, doc:getCurrentPage())
        assert.equals(last, selector._previous_indicator_word.pos0)
    end)
end)
