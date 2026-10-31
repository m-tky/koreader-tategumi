-- Latin ruby must reserve its visible inline depth, not one em per Latin
-- character. Hidden <rp> fallback text must not change the following glyph's
-- position. Compare against plain text and an otherwise identical ruby.
describe("Vertical text: Latin ruby uses horizontal advance #latin_ruby_advance", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui, path

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja"><head><style>
html, body { margin: 0; padding: 0; writing-mode: vertical-rl; }
p { margin: 0; text-align: left; font-family: "Noto Sans CJK SC"; }
rt { font-size: 50%; }
</style></head><body>
<p>甲Nachbild乙</p>
<p>甲<ruby>Nachbild<rt>ナハビルド</rt></ruby>丙</p>
<p>甲<ruby>Nachbild<rp>（fallback</rp><rt>ナハビルド</rt><rp>fallback）</rp></ruby>丁</p>
</body></html>]])
        f:close()
        local document = DocumentRegistry:openDocument(path)
        document._document:resetVertRubyAdvDiff()
        readerui = ReaderUI:new{dimen = Screen:getSize(), document = document}
        UIManager:show(readerui)
        document:setFontSize(32)
        document:setVisiblePageCount(1)
        readerui.rolling:onUpdatePos()
        fastforward_ui_events()
        assert.is_true(document:isVerticalText())
    end)

    after_each(function()
        if readerui then readerui:onClose(); readerui = nil end
        UIManager:quit()
        if path then os.remove(path) end
    end)

    local function depth_before_marker(index, marker)
        local doc = readerui.document
        -- Compare the CJK glyphs surrounding the Latin run. A ruby base's
        -- own xpointer is offset sideways by its annotation box.
        local hits = doc:findAllText("甲", false, 0, 10, false)
        assert.truthy(hits and hits[index], "preceding character missing")
        local markers = doc:findAllText(marker, false, 0, 10, false)
        assert.truthy(markers and markers[1], "following character missing")
        local page = doc:getPageFromXPointer(hits[index].start)
        assert.equals(page, doc:getPageFromXPointer(markers[1].start), "sample must fit on one page")
        readerui.rolling:onGotoPage(page)
        fastforward_ui_events()
        local y, x = doc:getScreenPositionFromXPointer(hits[index].start)
        local next_y, next_x = doc:getScreenPositionFromXPointer(markers[1].start)
        assert.is_true(math.abs(x - next_x) <= 2,
            string.format("sample %d must fit in one column: (%d,%d) -> (%d,%d)", index, x, y, next_x, next_y))
        assert.is_true(next_y > y, "following character must advance down the column")
        return next_y - y
    end

    it("leaves no oversized gap after a Latin ruby base #latin_advance", function()
        local plain = depth_before_marker(1, "乙")
        local ruby = depth_before_marker(2, "丙")
        -- Plain Latin can receive CJK/Latin auto-spacing on either side;
        -- a ruby box need not have that spacing. Allow up to one body em of
        -- reduction, but reject a collapsed advance or an oversized gap.
        local spacing_allowance = readerui.document:getFontSize()
        assert.is_true(ruby >= plain - spacing_allowance and ruby <= plain + 2,
            string.format("Latin ruby reserves %dpx before next character; plain text reserves %dpx", ruby, plain))
        local total_px = readerui.document._document:getVertRubyAdvDiff()
        assert.is_true(total_px > 0, "fixture must exercise reduced Latin ruby advance")
    end)

    it("ignores rp fallback when positioning the next character #latin_rp_advance", function()
        local ruby = depth_before_marker(2, "丙")
        local fallback = depth_before_marker(3, "丁")
        assert.is_true(math.abs(fallback - ruby) <= 2,
            string.format("hidden rp text changed inline depth from %dpx to %dpx", ruby, fallback))
    end)
end)
