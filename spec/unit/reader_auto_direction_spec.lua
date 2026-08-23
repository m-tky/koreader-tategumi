describe("Reader auto page direction", function()
    local BD, Notification, PageDirection, ReaderAutoDirection

    local function makeConfig(values)
        local config = { values = values or {} }
        function config:has(name)
            return self.values[name] ~= nil
        end
        function config:readSetting(name)
            return self.values[name]
        end
        function config:isTrue(name)
            return self.values[name] == true
        end
        function config:saveSetting(name, value)
            self.values[name] = value
        end
        function config:makeTrue(name)
            self.values[name] = true
        end
        return config
    end

    local function makeDetector(inverse_reading_order)
        local view = {
            inverse_reading_order = inverse_reading_order or false,
            setup_calls = 0,
            sync_calls = 0,
        }
        function view:refreshPageTurnInput()
            self.setup_calls = self.setup_calls + 1
        end
        function view:syncProgressBarDirection()
            self.sync_calls = self.sync_calls + 1
        end
        return ReaderAutoDirection:new{
            document = { file = "book.cbz" },
            view = view,
        }, view
    end

    setup(function()
        require("commonrequire")
        BD = require("ui/bidi")
        Notification = require("ui/widget/notification")
        PageDirection = require("util/page_direction")
        ReaderAutoDirection = require("apps/reader/modules/reader_auto_direction")
    end)

    before_each(function()
        stub(Notification, "notify")
    end)

    it("applies and versions a newly detected RTL direction", function()
        stub(PageDirection, "getDirection").returns("rtl")
        local detector, view = makeDetector(false)
        local config = makeConfig()

        detector:onReadSettings(config)

        assert.is_true(view.inverse_reading_order)
        assert.equals(1, view.setup_calls)
        assert.equals(1, view.sync_calls)
        assert.equals("rtl", config.values.direction_auto_detected)
        assert.equals(ReaderAutoDirection.DETECTION_VERSION,
            config.values.direction_auto_detected_version)
    end)

    it("rechecks a legacy none result with the corrected detector", function()
        stub(PageDirection, "getDirection").returns("rtl")
        local detector, view = makeDetector(false)
        local config = makeConfig({ direction_auto_detected = "none" })

        detector:onReadSettings(config)

        assert.is_true(view.inverse_reading_order)
        assert.equals("rtl", config.values.direction_auto_detected)
        assert.equals(ReaderAutoDirection.DETECTION_VERSION,
            config.values.direction_auto_detected_version)
    end)

    it("does not rescan a result from the current detector", function()
        stub(PageDirection, "getDirection")
        local detector = makeDetector(false)
        local config = makeConfig({
            direction_auto_detected = "none",
            direction_auto_detected_version = ReaderAutoDirection.DETECTION_VERSION,
        })

        detector:onReadSettings(config)

        assert.stub(PageDirection.getDirection).was_not_called()
    end)

    it("does not mistake an automatically serialized LTR default for a user override", function()
        stub(PageDirection, "getDirection").returns("rtl")
        local detector, view = makeDetector(false)
        local config = makeConfig({ inverse_reading_order = false })

        detector:onReadSettings(config)

        assert.stub(PageDirection.getDirection).was_called(1)
        assert.is_true(view.inverse_reading_order)
        assert.equals("rtl", config.values.direction_auto_detected)
    end)

    it("preserves an explicit per-document reading-order override", function()
        stub(PageDirection, "getDirection")
        local detector, view = makeDetector(false)
        local config = makeConfig({
            inverse_reading_order = false,
            page_direction_user_override = true,
        })

        detector:onReadSettings(config)

        assert.stub(PageDirection.getDirection).was_not_called()
        assert.is_false(view.inverse_reading_order)
        assert.is_nil(config.values.direction_auto_detected_version)
    end)

    it("marks reading-order toggles as explicit user overrides", function()
        local ReaderView = require("apps/reader/modules/readerview")
        local config = makeConfig()
        local view = {
            inverse_reading_order = false,
            ui = { doc_settings = config },
            refresh_calls = 0,
            refreshPageTurnInput = function(self)
                self.refresh_calls = self.refresh_calls + 1
            end,
            syncProgressBarDirection = function() end,
        }

        ReaderView.onToggleReadingOrder(view, true)

        assert.is_true(config.values.page_direction_user_override)
        assert.is_true(view.inverse_reading_order)
        assert.equals(1, view.refresh_calls)
    end)

    it("uses the reading order for document page progression", function()
        local ReaderView = require("apps/reader/modules/readerview")
        stub(BD, "mirroredUILayout").returns(false)
        local view = {
            inverse_reading_order = false,
            invert_ui_layout = false,
            document = {
                isVerticalText = function() return false end,
            },
        }

        assert.is_false(ReaderView.shouldInvertPageProgression(view))

        view.inverse_reading_order = true
        assert.is_true(ReaderView.shouldInvertPageProgression(view))
    end)

    it("versions an unknown result without changing the page direction", function()
        stub(PageDirection, "getDirection").returns(nil)
        local detector, view = makeDetector(false)
        local config = makeConfig()

        detector:onReadSettings(config)

        assert.is_false(view.inverse_reading_order)
        assert.equals(0, view.setup_calls)
        assert.equals("none", config.values.direction_auto_detected)
        assert.equals(ReaderAutoDirection.DETECTION_VERSION,
            config.values.direction_auto_detected_version)
    end)
end)
