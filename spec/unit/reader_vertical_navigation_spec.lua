describe("Vertical reader navigation regressions", function()
    local BD, Geom, ReaderView, ReaderHighlight, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        BD = require("ui/bidi")
        Geom = require("ui/geometry")
        ReaderView = require("apps/reader/modules/readerview")
        ReaderHighlight = require("apps/reader/modules/readerhighlight")
        UIManager = require("ui/uimanager")
    end)

    local function viewFixture(vertical, override)
        return setmetatable({
            inverse_reading_order = false,
            invert_ui_layout = false,
            document = { hasVerticalContent = function() return vertical end },
            ui = {
                rolling = {},
                doc_settings = { isTrue = function() return override end },
            },
        }, { __index = ReaderView })
    end

    it("returns relative progression inversion and lets manual layout reverse it", function()
        for _, mirrored in ipairs({false, true}) do
            stub(BD, "mirroredUILayout").returns(mirrored)
            for _, vertical in ipairs({false, true}) do
                for _, override in ipairs({false, true}) do
                    local view = viewFixture(vertical, override)
                    for _, rtl in ipairs({false, true}) do
                        view.inverse_reading_order = rtl ~= mirrored
                        for _, manual in ipairs({false, true}) do
                            view.invert_ui_layout = manual
                            local expected_rtl = (vertical and not override) or rtl
                            local inversion = view:shouldInvertPageProgression()
                            -- Consumers XOR this flag with the current UI mirroring.
                            assert.equals(expected_rtl ~= manual, inversion ~= mirrored)
                            local footer_inversion
                            view.footer = { invertProgressBar = function(_, value) footer_inversion = value end }
                            view:syncProgressBarDirection()
                            assert.equals(inversion, footer_inversion)
                        end
                    end
                end
            end
            BD.mirroredUILayout:revert()
        end
    end)

    it("preserves explicit LTR tap zones but defaults vertical books to RTL", function()
        local previous = G_reader_settings:readSetting("page_turns_tap_zones")
        G_reader_settings:saveSetting("page_turns_tap_zones", "left_right")
        finally(function() G_reader_settings:saveSetting("page_turns_tap_zones", previous) end)
        for _, mirrored in ipairs({false, true}) do
            stub(BD, "mirroredUILayout").returns(mirrored)
            local ltr_view = viewFixture(false, false)
            ltr_view.inverse_reading_order = mirrored
            local ltr_forward, ltr_backward = ltr_view:getTapZones()
            for _, override in ipairs({false, true}) do
                local view = viewFixture(true, override)
                view.inverse_reading_order = mirrored
                local forward, backward = view:getTapZones()
                if override then
                    assert.same(ltr_forward, forward)
                    assert.same(ltr_backward, backward)
                else
                    assert.is_true(forward.ratio_x < backward.ratio_x)
                end
                view.inverse_reading_order = not mirrored
                forward, backward = view:getTapZones()
                assert.is_true(forward.ratio_x < backward.ratio_x)
            end
            BD.mirroredUILayout:revert()
        end
    end)

    local function assertDirectionPersists(choose_ltr)
        local Registry = require("document/documentregistry")
        local ReaderUI = require("apps/reader/readerui")
        local DocSettings = require("docsettings")
        local Screen = require("device").screen
        local path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        local reader
        finally(function()
            if reader then reader:onClose() end
            UIManager:quit()
            UIManager._exit_code = nil
            DocSettings:open(path):purge()
            os.remove(path)
        end)
        local f = assert(io.open(path, "wb"))
        f:write('<html xmlns="http://www.w3.org/1999/xhtml"><head><style>' ..
            'body { writing-mode: vertical-rl; }</style></head><body><p>' ..
            ("縦書きの本文です。"):rep(100) .. '</p></body></html>')
        f:close()
        local function open()
            reader = ReaderUI:new{ dimen = Screen:getSize(), document = Registry:openDocument(path) }
            UIManager:show(reader)
            fastforward_ui_events()
            assert.is_true(reader.document:hasVerticalContent())
        end
        open()
        assert.equals(not BD.mirroredUILayout(), reader.view.inverse_reading_order)
        reader.view:onToggleUILayoutMiroring(false)
        local chosen_inversion = (not choose_ltr) ~= BD.mirroredUILayout()
        reader.view:onToggleReadingOrder(chosen_inversion)
        assert.is_false(reader.view.inverse_reading_order_forced)
        reader:onClose()
        reader = nil
        open()
        assert.is_true(reader.doc_settings:isTrue("page_direction_user_override"))
        assert.equals(chosen_inversion, reader.view.inverse_reading_order)
        assert.equals(not choose_ltr, reader.view:shouldInvertPageProgression() ~= BD.mirroredUILayout())
        local forward, backward = reader.view:getTapZones()
        assert.equals(choose_ltr, forward.ratio_x > backward.ratio_x)
        assert.equals("page", reader.view.view_mode)
    end

    it("keeps an explicit LTR choice after closing and reopening a vertical book", function()
        assertDirectionPersists(true)
    end)

    it("persists an explicit choice matching the automatic RTL direction", function()
        assertDirectionPersists(false)
    end)

    local function highlightFixture(modes, start_page)
        local page = start_page or 1
        local anchor = page * 100 + 10
        local doc = {}
        function doc:isVerticalAtPosition() return modes[page] ~= false end
        function doc:getPageMargins() return { left = 20, right = 20, top = 20, bottom = 20 } end
        function doc:getVisiblePageCount() return 1 end
        function doc:getCurrentPage() return page end
        function doc:getXPointer() return page * 100 end
        function doc:getTextFromPositions(_, _, lua_highlight)
            self.lua_highlight = lua_highlight
            return { pos0 = page * 100 + 10, pos1 = page * 100 + 20, text = "page text", sboxes = {} }
        end
        function doc:getWordFromPosition(pos)
            if pos.x == 300 then return nil end -- whitespace
            return { pos0 = page * 100 + pos.y, pos1 = page * 100 + pos.y + 1 }
        end
        function doc:compareXPointers(a, b) return a < b and 1 or (a > b and -1 or 0) end
        function doc:getTextFromXPointers(a, b) return a .. ":" .. b end
        function doc:getScreenBoxesFromPositions() return { { x = 100, y = 100, w = 20, h = 20 } } end
        function doc:clearSelection() end
        local highlight = setmetatable({
            screen_w = 600, screen_h = 800,
            hold_pos = { x = 400, y = 200, page = page },
            selected_text_start_xpointer = anchor,
            selected_text_start_word_end_xpointer = anchor + 1,
            selected_text = { pos0 = anchor, pos1 = anchor + 1, text = "initial word" },
            allow_corner_scroll = true,
            view = {
                highlight = { temp = {} }, view_mode = "page",
                getScreenPageArea = function() return Geom:new{ w = 600, h = 800 } end,
                screenToPageTransform = function(_, pos) return pos end,
            },
            ui = {
                document = doc,
                rolling = {
                    _gotoPage = function(_, target) page = target end,
                    onGotoXPointer = function(_, xp, marker)
                        doc.restored_anchor = marker
                        page = xp / 100
                    end,
                },
                keyselection = { isActive = function() return false end },
            },
            _resetHoldTimer = function() end,
        }, { __index = ReaderHighlight })
        local function pan(x, y)
            highlight:onHoldPan(nil, { pos = Geom:new{ x = x, y = y } })
        end
        return highlight, doc, pan
    end

    it("restores the initial page after repeated vertical corner jumps", function()
        stub(UIManager, "setDirty")
        local highlight, doc, pan = highlightFixture({true, true, true})
        pan(400, 200)
        pan(1, 799)
        assert.equals(2, doc:getCurrentPage())
        local restore = highlight.restore_page_mode_func
        pan(400, 200)
        pan(1, 799)
        assert.equals(3, doc:getCurrentPage())
        assert.equals(restore, highlight.restore_page_mode_func)
        pan(400, 200)
        pan(599, 1)
        assert.equals(2, doc:getCurrentPage())
        highlight:clear()
        assert.equals(1, doc:getCurrentPage())
        assert.equals(110, doc.restored_anchor)
        assert.is_nil(highlight.holdpan_vertical_page_jump)
        assert.is_nil(highlight.restore_page_mode_func)
    end)

    it("keeps the initial word end when dragging back to a horizontal page", function()
        stub(UIManager, "setDirty")
        local highlight, doc, pan = highlightFixture({false, true}, 2)
        pan(400, 200)
        pan(599, 1)
        assert.equals(1, doc:getCurrentPage())
        pan(400, 50)
        assert.equals(150, highlight.selected_text.pos0)
        assert.equals(211, highlight.selected_text.pos1)
        highlight:clear()
        assert.equals(2, doc:getCurrentPage())
        assert.equals(210, doc.restored_anchor)
    end)

    it("does not reanchor ordinary horizontal scroll-mode selection", function()
        stub(UIManager, "setDirty")
        local highlight, _, pan = highlightFixture({false})
        highlight.allow_corner_scroll = false
        highlight.restore_page_mode_func = function() end
        highlight.selected_text_start_xpointer = 1
        pan(400, 200)
        assert.equals(110, highlight.selected_text.pos0)
        assert.equals(120, highlight.selected_text.pos1)
        assert.is_nil(highlight.holdpan_vertical_page_jump)
    end)

    it("keeps the original anchor when a vertical drag reaches horizontal text", function()
        stub(UIManager, "setDirty")
        local highlight, doc, pan = highlightFixture({true, false, false})
        pan(400, 200)
        pan(1, 799)
        assert.equals(2, doc:getCurrentPage())
        pan(400, 200)
        assert.equals(110, highlight.selected_text.pos0)
        assert.equals(401, highlight.selected_text.pos1)
        pan(400, 100) -- Shrink the endpoint independently of the stale hold position.
        assert.equals(110, highlight.selected_text.pos0)
        assert.equals(301, highlight.selected_text.pos1)
        assert.truthy(doc.lua_highlight)
        assert.same(doc:getScreenBoxesFromPositions(), highlight.view.highlight.temp[1])
        pan(300, 100) -- Whitespace must keep the last valid cross-page range.
        assert.equals(110, highlight.selected_text.pos0)
        assert.equals(301, highlight.selected_text.pos1)
        pan(599, 799) -- Horizontal next-page corner must keep the discrete-jump session.
        assert.equals(3, doc:getCurrentPage())
        highlight:clear()
        assert.equals(1, doc:getCurrentPage())
    end)
end)
