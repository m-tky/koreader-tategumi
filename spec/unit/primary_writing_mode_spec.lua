--[[--
Kindle-compatible OPF primary-writing-mode defaults.

Run via:
  ./kodev test front -f "primary writing mode"
--]]

describe("EPUB primary writing mode #primary_writing_mode", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function open_and_is_vertical(epub_path)
        local f = io.open(epub_path, "r")
        if not f then return nil end
        f:close()
        local doc = DocumentRegistry:openDocument(epub_path)
        assert(doc, "failed to open " .. epub_path)
        local readerui = ReaderUI:new{ dimen = Screen:getSize(), document = doc }
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()
        local is_vertical = doc:isVerticalText()
        readerui:onClose()
        UIManager:quit()
        return is_vertical
    end

    it("uses vertical-rl primary-writing-mode when the content has no writing-mode CSS #primary_writing_mode", function()
        local is_vertical = open_and_is_vertical(
            "spec/front/unit/data/fixtures/vertical_text/primary_writing_mode_test.epub")
        if is_vertical == nil then pending("primary-writing-mode fixture missing"); return end
        assert.is_true(is_vertical)
    end)

    it("keeps primary-writing-mode after reopening from the document cache #primary_writing_mode", function()
        local epub_path = "spec/front/unit/data/fixtures/vertical_text/primary_writing_mode_test.epub"
        local cold_open = open_and_is_vertical(epub_path)
        if cold_open == nil then pending("primary-writing-mode fixture missing"); return end
        assert.is_true(cold_open)
        assert.is_true(open_and_is_vertical(epub_path))
    end)

    it("lets explicit author CSS override primary-writing-mode #primary_writing_mode", function()
        local is_vertical = open_and_is_vertical(
            "spec/front/unit/data/fixtures/vertical_text/primary_writing_mode_css_override_test.epub")
        if is_vertical == nil then pending("primary-writing-mode CSS fixture missing"); return end
        assert.is_false(is_vertical)
    end)
end)
