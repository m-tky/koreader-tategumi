--[[--
Vertical text: outside list marker formatting.

Regression test for issue #20: outside list markers created their own
LFormattedText and called Format() without passing the effective
writing-mode, so inherited vertical-rl documents formatted those markers as
horizontal text.

The fixture sets writing-mode only on <body>, leaving <li> at inherit. It
contains one text-only list item (erm_final path) and one block-child list
item (erm_block path). The renderer exposes a diagnostic that counts how many
outside markers were formatted vertically.

Run via:
  ./kodev test front -f "list marker outside"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: outside list markers #list_marker_outside", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/list_marker_outside_test.epub"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    it("formats outside markers with vertical writing-mode in vertical-rl docs", function()
        if not lfs.attributes(epub_path) then
            pending("list_marker_outside_test.epub not found")
            return
        end

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        local doc = readerui.document
        doc._document:resetListMarkerDiag()
        UIManager:show(readerui)
        fastforward_ui_events()

        local pages_to_visit = math.min(2, doc:getPageCount())
        for page = 1, pages_to_visit do
            readerui.rolling:onGotoPage(page)
            fastforward_ui_events()
        end

        local vert_ok, vert_miss = doc._document:getListMarkerDiagStats()
        print(string.format(
            "\n[list_marker_outside] vert_ok=%d vert_miss=%d",
            vert_ok, vert_miss))

        assert.are.equal(0, vert_miss,
            string.format("outside markers still formatted horizontally in vertical doc: vert_ok=%d vert_miss=%d",
                vert_ok, vert_miss))
        assert.is_true(vert_ok >= 2,
            string.format("expected both outside marker paths to format vertically, got vert_ok=%d", vert_ok))

        readerui:closeDocument()
        readerui:onClose()
    end)
end)
