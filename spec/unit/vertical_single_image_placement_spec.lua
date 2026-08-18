--[[--
Vertical-rl full-page image placement regression.

The fixture declares vertical-rl only through EPUB metadata, so the final
image block itself keeps writing-mode: inherit. This reproduces two bugs:
  * a context-free cache lookup reformatted the image as horizontal at draw;
  * vertical text-align:center used the image width instead of its inline-axis
    height, leaving the illustration high and partly outside the page clip.

The C++ diagnostic records the same draw/clip coordinates emitted by
KO_DEBUG_VERT_BG. The assertions intentionally avoid screenshot comparison.
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: single full-page image placement", function()
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/single_image_placement_test.epub"
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    after_each(function()
        if readerui then
            readerui:onClose()
            readerui = nil
        end
        UIManager:quit()
    end)

    it("keeps an inherited-mode image inside the clip and vertically centered #single_image_placement", function()
        if not lfs.attributes(epub_path) then
            pending("single_image_placement_test.epub fixture missing")
            return
        end

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        local doc = readerui.document
        assert.is_true(doc._document:isVerticalText(),
            "fixture metadata should select vertical-rl")
        doc._document:resetVertSingleImagePlacement()

        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()

        local samples, clipped, max_overflow, max_center_error =
            doc._document:getVertSingleImagePlacement()
        print(string.format(
            "[single_image_placement] samples=%d clipped=%d max_overflow=%d center_error=%d",
            samples, clipped, max_overflow, max_center_error))

        assert.is_true(samples > 0,
            "single image was not drawn through the vertical formatter")
        assert.are.equal(0, clipped,
            string.format("single image exceeded the page clip by %d px", max_overflow))
        assert.is_true(max_center_error <= 8,
            string.format("single image is not vertically centered (gap delta: %d px)",
                max_center_error))
    end)
end)
