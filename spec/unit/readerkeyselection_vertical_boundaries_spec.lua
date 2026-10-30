describe("Vertical text key selection boundaries", function()
    local Device, Registry, ReaderUI, UIManager, Geom, Event, Key
    local cleanups

    local function cleanup(callback)
        cleanups[#cleanups + 1] = callback
    end

    before_each(function() cleanups = {} end)
    after_each(function()
        for i = #cleanups, 1, -1 do cleanups[i]() end
    end)

    setup(function()
        require("commonrequire")
        disable_plugins()
        Device = require("device")
        require("document/canvascontext"):init(Device)
        Registry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Geom = require("ui/geometry")
        Event = require("ui/event")
        Key = require("device/key")
    end)

    local function open(body)
        local path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        cleanup(function() os.remove(path) end)
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
            html, body { margin: 0; padding: 0; }
            p { margin: 0; }
            .vertical { writing-mode: vertical-rl; }
            .horizontal { writing-mode: horizontal-tb; }
            .page { page-break-before: always; }
            </style></head><body>]], body, [[</body></html>]])
        f:close()
        local reader = ReaderUI:new{ dimen = Device.screen:getSize(), document = Registry:openDocument(path) }
        cleanup(function()
            reader:onClose()
            if ReaderUI.instance == reader then reader:onCloseWidget() end
            UIManager:quit()
            UIManager._exit_code = nil
        end)
        UIManager:show(reader)
        reader.document:setVisiblePageCount(1)
        reader.document:setFontSize(26)
        fastforward_ui_events()
        return reader
    end

    local function locate(doc, text)
        local hits = doc:findAllText(text, false, 0, 100, false)
        assert.truthy(hits and hits[1], "missing fixture text: " .. text)
        return hits[1]
    end

    local function indicatorRect(box)
        -- Fixed pixels are intentional: these tests assert native screen geometry.
        local side = 4
        return Geom:new{ x = box.x + (box.w - side) / 2, y = box.y + (box.h - side) / 2,
            w = side, h = side }
    end

    local function place(reader, xp)
        local doc, selector = reader.document, reader.keyselection
        local page = doc:getPageFromXPointer(xp)
        if doc:getVisiblePageCount() == 2 then
            -- Show both sides of a writing-mode transition without turning
            -- the displayed spread while the cursor crosses that transition.
            reader.rolling:_gotoPage(math.max(1, page - 1), true, true)
        else
            reader.rolling:_gotoPage(page)
        end
        selector:clearOverlay()
        local y, x = doc:getScreenPositionFromXPointer(xp)
        assert.truthy(x and y)
        local word = doc:getWordFromPosition({ x = x + 2, y = y + 2 }, true)
        assert.truthy(word and word.sbox)
        local boxes = doc:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
        word.segments = boxes
        local b = boxes[1]
        local rect = indicatorRect(b)
        if selector:isActive() then
            selector:_setIndicatorRect(rect)
        else
            selector:_beginIndicator(rect, Device.screen:getSize())
        end
        selector._previous_indicator_word = word
        selector._edge_dx, selector._edge_dy = nil, nil
        selector._vertical_selection_anchor_y = nil
        selector._last_move_was_vertical = false
        selector._vertical_move_anchor_x = nil
        return word
    end

    local function mode(reader)
        local r = reader.keyselection._current_indicator_pos
        return reader.document:isVerticalAtPosition({ x = r.x + r.w / 2, y = r.y + r.h / 2 })
    end

    local mixed = '<div class="vertical"><p>天地玄黄宇宙洪荒</p></div>' ..
        '<div class="horizontal"><p>春夏秋冬山川草木</p><p>花鳥風月日月星辰</p></div>' ..
        '<div class="vertical"><p>食物栄養健康生活</p></div>'

    it("switches to horizontal movement within the displayed spread forward", function()
        local reader = open(mixed)
        local doc, selector = reader.document, reader.keyselection
        doc:setVisiblePageCount(2)
        fastforward_ui_events()
        local first_horizontal = locate(doc, "春").start
        place(reader, doc:getPrevVisibleWordStart(first_horizontal))
        assert.is_true(mode(reader))
        selector:moveHighlightIndicator({ 0, 1 })
        assert.is_false(mode(reader))
        assert.equals(first_horizontal, selector._previous_indicator_word.pos0)
        local before = selector._current_indicator_pos:copy()
        selector:moveHighlightIndicator({ 1, 0 })
        assert.is_true(selector._current_indicator_pos.x > before.x)
        assert.near(before.y, selector._current_indicator_pos.y, 2)
        selector:moveHighlightIndicator({ -1, 0 })
        assert.near(before.x, selector._current_indicator_pos.x, 2)
    end)

    it("switches to horizontal movement within the displayed spread backward", function()
        local reader = open(mixed)
        local doc, selector = reader.document, reader.keyselection
        doc:setVisiblePageCount(2)
        fastforward_ui_events()
        local first_vertical = locate(doc, "食").start
        place(reader, first_vertical)
        selector:moveHighlightIndicator({ 0, -1 })
        assert.is_false(mode(reader))
        local before = selector._current_indicator_pos:copy()
        selector:moveHighlightIndicator({ -1, 0 })
        assert.is_true(selector._current_indicator_pos.x < before.x)
        assert.near(before.y, selector._current_indicator_pos.y, 2)
    end)

    it("does not continue a quick downward move along a horizontal row", function()
        local reader = open(mixed)
        local doc, selector = reader.document, reader.keyselection
        doc:setVisiblePageCount(2)
        fastforward_ui_events()
        local first_horizontal = locate(doc, "春").start
        place(reader, doc:getPrevVisibleWordStart(first_horizontal))
        selector:moveHighlightIndicator({ 0, 1 })
        local entry = selector._current_indicator_pos:copy()
        place(reader, doc:getPrevVisibleWordStart(first_horizontal))
        selector:moveHighlightIndicator({ 0, 1, true })
        assert.is_false(mode(reader))
        local after = selector._current_indicator_pos
        assert.is_true(after.y > entry.y + 2 or math.abs(after.x - entry.x) <= 2,
            "Down must not advance horizontally after entering horizontal text")
    end)

    it("does not continue a quick upward move along a horizontal row", function()
        local reader = open(mixed)
        local doc, selector = reader.document, reader.keyselection
        doc:setVisiblePageCount(2)
        fastforward_ui_events()
        local first_vertical = locate(doc, "食").start
        place(reader, first_vertical)
        selector:moveHighlightIndicator({ 0, -1 })
        local entry = selector._current_indicator_pos:copy()
        place(reader, first_vertical)
        selector:moveHighlightIndicator({ 0, -1, true })
        assert.is_false(mode(reader))
        local after = selector._current_indicator_pos
        assert.is_true(after.y < entry.y - 2 or math.abs(after.x - entry.x) <= 2,
            "Up must not advance horizontally after entering horizontal text")
    end)

    it("refreshes cursor position and height after F7/F6-equivalent page keys", function()
        local reader = open('<div class="vertical"><p>天地玄黄宇宙洪荒<br/>日月盈昃<br/>辰宿列張寒来暑往</p>' ..
            '<p class="page">食物栄養健康生活<br/>春夏秋冬<br/>山川草木花鳥風月</p></div>')
        local doc, selector = reader.document, reader.keyselection
        local dpad = stub(Device, "useDPadAsActionKeys", function() return true end)
        cleanup(function() dpad:revert() end)
        reader.rolling:registerKeyEvents()
        place(reader, locate(doc, "玄").start)
        selector:moveHighlightIndicator({ -1, 0 })
        assert.truthy(selector._vertical_selection_anchor_y)
        local old_page = doc:getCurrentPage()
        reader:handleEvent(Event:new("KeyPress", Key:new("LPgFwd", {})))
        assert.is_true(doc:getCurrentPage() > old_page)
        assert.is_nil(selector._vertical_selection_anchor_y)
        local xp = selector._previous_indicator_word.pos0
        assert.is_true(doc:isXPointerInCurrentPage(xp))
        selector:moveHighlightIndicator({ 0, 1 })
        assert.equals(doc:getNextVisibleWordStart(xp), selector._previous_indicator_word.pos0)
        selector:moveHighlightIndicator({ 0, -1 })
        assert.equals(xp, selector._previous_indicator_word.pos0)
        reader:handleEvent(Event:new("KeyPress", Key:new("LPgBack", {})))
        assert.equals(old_page, doc:getCurrentPage())
        assert.is_nil(selector._vertical_selection_anchor_y)
        local before = selector._current_indicator_pos:copy()
        selector:moveHighlightIndicator({ -1, 0, true })
        assert.near(before.y + before.h / 2, selector._vertical_selection_anchor_y, 2)
        assert.is_true(doc:isXPointerInCurrentPage(selector._previous_indicator_word.pos0))
    end)

    it("visits both fragments of an overlong Latin word across columns", function()
        local token = ("supercalifragilisticexpialidocious"):rep(8)
        local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
        local doc, selector = reader.document, reader.keyselection
        local word = place(reader, locate(doc, token).start)
        local boxes = word.segments
        assert.is_true(#boxes > 1, "fixture must split the overlong word into physical fragments")
        assert.is_true(math.abs(boxes[1].x - boxes[2].x) > 2, "fragments must occupy different columns")
        local start_xp = word.pos0
        selector:moveHighlightIndicator({ 0, 1 })
        assert.equals(start_xp, selector._previous_indicator_word.pos0,
            "Down must visit the next fragment before skipping to the next word")
        assert.near(boxes[2].x + boxes[2].w / 2, selector._current_indicator_pos.x + 2, 2)
        selector:moveHighlightIndicator({ 0, -1 })
        assert.equals(start_xp, selector._previous_indicator_word.pos0)
        assert.near(boxes[1].x + boxes[1].w / 2, selector._current_indicator_pos.x + 2, 2)
    end)

    it("can move backward from a split word's second column to its first", function()
        local token = ("supercalifragilisticexpialidocious"):rep(8)
        local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
        local doc, selector = reader.document, reader.keyselection
        local word = place(reader, locate(doc, token).start)
        assert.is_true(#word.segments > 1, "fixture must span multiple columns")
        local b = word.segments[2]
        selector:_setIndicatorRect(indicatorRect(b))
        selector:moveHighlightIndicator({ 0, -1 })
        assert.equals(word.pos0, selector._previous_indicator_word.pos0,
            "Up must visit the previous fragment before leaving the word")
        local first = word.segments[1]
        assert.near(first.x + first.w / 2, selector._current_indicator_pos.x + 2, 2)
    end)

    for _, direction in ipairs({ 1, -1 }) do
        it("counts split-word fragments during quick movement (direction=" .. direction .. ")", function()
            local token = ("supercalifragilisticexpialidocious"):rep(8)
            local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
            local doc, selector = reader.document, reader.keyselection
            local word = place(reader, locate(doc, token).start)
            assert.is_true(#word.segments >= 5, "fixture must provide at least five fragments")
            local origin = word.segments[direction > 0 and 1 or 5]
            selector:_setIndicatorRect(indicatorRect(origin))
            selector:moveHighlightIndicator({ 0, direction, true })
            assert.equals(word.pos0, selector._previous_indicator_word.pos0)
            local target = word.segments[direction > 0 and 5 or 1]
            assert.near(target.x + target.w / 2, selector._current_indicator_pos.x + 2, 2)
        end)
    end

    it("moves left and right between a split word's columns", function()
        local token = ("supercalifragilisticexpialidocious"):rep(8)
        local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
        local doc, selector = reader.document, reader.keyselection
        local word = place(reader, locate(doc, token).start)
        assert.is_true(#word.segments >= 5, "fixture must provide at least five fragments")
        for _, quick in ipairs({ false, true }) do
            place(reader, word.pos0)
            local first = selector._current_indicator_pos:copy()
            selector:moveHighlightIndicator({ -1, 0, quick })
            assert.equals(word.pos0, selector._previous_indicator_word.pos0)
            local target = word.segments[2]
            if quick then
                for _, segment in ipairs(word.segments) do
                    target = segment
                    if first.x + first.w / 2 - segment.x - segment.w / 2 >= reader.view.visible_area.w / 5 then break end
                end
            end
            assert.near(target.x + target.w / 2, selector._current_indicator_pos.x + 2, 2)
            selector:moveHighlightIndicator({ 1, 0, quick })
            assert.equals(word.pos0, selector._previous_indicator_word.pos0)
            assert.near(first.x, selector._current_indicator_pos.x, 2)
            assert.near(first.y, selector._current_indicator_pos.y, 2)
        end
    end)

    for _, case in ipairs({ {false, "text"}, {false, "column"}, {true, "text"}, {true, "column"} }) do
        local quick, axis = unpack(case)
        it("stops at the page end even when a word continues (" .. axis .. ", quick=" .. tostring(quick) .. ")", function()
            local token = ("supercalifragilisticexpialidocious"):rep(40)
            local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
            local doc, selector = reader.document, reader.keyselection
            local word = place(reader, locate(doc, token).start)
            local page = doc:getCurrentPage()
            assert.is_true(doc:getPageFromXPointer(word.pos1) > page, "fixture must split the word across pages")
            local b = word.segments[#word.segments]
            selector:_setIndicatorRect(indicatorRect(b))
            for _ = 1, 5 do
                selector:moveHighlightIndicator({ axis == "column" and -1 or 0, axis == "text" and 1 or 0, quick })
            end
            assert.equals(page, doc:getCurrentPage(), "a split word must not cause an automatic page turn")
            assert.equals(word.pos0, selector._previous_indicator_word.pos0)
            assert.near(b.x + b.w / 2, selector._current_indicator_pos.x + 2, 2)
        end)

        it("stops at the page start even when a word began earlier (" .. axis .. ", quick=" .. tostring(quick) .. ")", function()
            local token = ("supercalifragilisticexpialidocious"):rep(40)
            local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
            local doc, selector = reader.document, reader.keyselection
            local word = place(reader, locate(doc, token).start)
            local first_page = doc:getCurrentPage()
            assert.is_true(doc:getPageFromXPointer(word.pos1) > first_page, "fixture must split the word across pages")
            reader.rolling:_gotoPage(first_page + 1)
            selector:clearOverlay()
            word.segments = doc:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
            assert.truthy(word.segments and word.segments[1])
            local b = word.segments[1]
            word.sbox = b
            selector:_setIndicatorRect(indicatorRect(b))
            for _ = 1, 5 do
                selector:moveHighlightIndicator({ axis == "column" and 1 or 0, axis == "text" and -1 or 0, quick })
            end
            assert.equals(first_page + 1, doc:getCurrentPage())
            assert.equals(word.pos0, selector._previous_indicator_word.pos0)
            assert.near(b.x + b.w / 2, selector._current_indicator_pos.x + 2, 2)
        end)
    end

    for _, mode_name in ipairs({ "horizontal", "vertical" }) do
        it("uses one fifth of the viewport for quick cross-line movement (" .. mode_name .. ")", function()
            local reader = open('<div class="' .. mode_name .. '"><p>' ..
                ("天地玄黄宇宙洪荒日月盈昃辰宿列張寒来暑往"):rep(30) .. '</p></div>')
            local selector = reader.keyselection
            place(reader, locate(reader.document, "天地").start)
            local initial = selector._current_indicator_pos:copy()
            local vertical = mode_name == "vertical"
            selector:moveHighlightIndicator({ vertical and -1 or 0, vertical and 0 or 1, true })
            local after = selector._current_indicator_pos
            local dimension = vertical and reader.view.visible_area.w or reader.view.visible_area.h
            local distance = vertical and initial.x - after.x or after.y - initial.y
            assert.is_true(distance > 0)
            assert.near(dimension / 5, distance, 55,
                "quick cross-line movement must scale with viewport size, not a fixed column count")
        end)
    end

    it("starts the crosshairs on the nearest vertical fragment, not a horizontal head/tail", function()
        local token = ("supercalifragilisticexpialidocious"):rep(8)
        local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
        local word = place(reader, locate(reader.document, token).start)
        assert.is_true(#word.segments > 2)
        local b = word.segments[2]
        local selector = reader.keyselection
        selector:_setIndicatorRect(indicatorRect(b))
        selector:stopHighlightIndicator(true)
        assert.is_true(selector:startHighlightIndicator())
        assert.near(b.x + b.w / 2, selector._current_indicator_pos.x + 2, 2)
        assert.near(b.y + b.h / 2, selector._current_indicator_pos.y + 2, 2)
        assert.is_nil(selector._previous_indicator_word.is_split_fragment)
        selector:moveHighlightIndicator({ 0, 1 })
        local next_box = word.segments[3]
        assert.near(next_box.x + next_box.w / 2, selector._current_indicator_pos.x + 2, 2)
    end)

    it("relocates onto a visible vertical fragment after ordinary page turns", function()
        local token = ("supercalifragilisticexpialidocious"):rep(40)
        local reader = open('<div class="vertical"><p>天地 ' .. token .. ' 宇宙</p></div>')
        local doc, selector = reader.document, reader.keyselection
        local dpad = stub(Device, "useDPadAsActionKeys", function() return true end)
        cleanup(function() dpad:revert() end)
        reader.rolling:registerKeyEvents()
        local word = place(reader, locate(doc, token).start)
        local first_page = doc:getCurrentPage()
        for _, key in ipairs({ "LPgFwd", "LPgBack" }) do
            reader:handleEvent(Event:new("KeyPress", Key:new(key, {})))
            assert.equals(first_page + (key == "LPgFwd" and 1 or 0), doc:getCurrentPage())
            assert.equals(word.pos0, selector._previous_indicator_word.pos0)
            assert.is_nil(selector._previous_indicator_word.is_split_fragment)
            local r = selector._current_indicator_pos
            local on_fragment = false
            for _, b in ipairs(doc:getScreenBoxesFromPositions(word.pos0, word.pos1, true)) do
                if math.abs(r.x + r.w / 2 - b.x - b.w / 2) < 2
                        and math.abs(r.y + r.h / 2 - b.y - b.h / 2) < 2 then
                    on_fragment = true
                end
            end
            assert.is_true(on_fragment, "page-turn relocation must center on a visible fragment")
        end
    end)

    it("visits a rotated Latin word intact and can move back to it", function()
        local reader = open('<div class="vertical"><p>天地玄黄 Nachbild 宇宙洪荒 Geschehen 日月盈昃</p></div>')
        local doc, selector = reader.document, reader.keyselection
        local hit = locate(doc, "Nachbild")
        place(reader, hit.start)
        assert.is_true(mode(reader))
        assert.equals("Nachbild", selector._previous_indicator_word.word)
        local initial = selector._current_indicator_pos:copy()
        local xp = selector._previous_indicator_word.pos0
        selector:moveHighlightIndicator({ 0, 1 })
        assert.equals(doc:getNextVisibleWordStart(xp), selector._previous_indicator_word.pos0)
        selector:moveHighlightIndicator({ 0, -1 })
        assert.equals(xp, selector._previous_indicator_word.pos0)
        assert.near(initial.x, selector._current_indicator_pos.x, 2)
        assert.near(initial.y, selector._current_indicator_pos.y, 2)
        selector:moveHighlightIndicator({ 0, 1, true })
        selector:moveHighlightIndicator({ 0, -1, true })
        assert.equals(xp, selector._previous_indicator_word.pos0)
    end)
end)
