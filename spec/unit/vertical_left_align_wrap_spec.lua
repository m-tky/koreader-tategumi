-- Regression coverage for koreader-tategumi issue #74.
--
-- A ragged (left/top-aligned) vertical column used to borrow the shrink
-- capacity reserved for justified JFM spacing while deciding its wrap point.
-- Draw does not apply that shrink to ragged columns, so the last logical
-- character could land beyond the regular clip and disappear.  This checks
-- layout coordinates rather than screenshot pixels: ン and プ must start the
-- same follow-up column, and the complete source text must remain selectable.

describe("Vertical left-aligned wrapping #vertical_left_align_wrap", function()
    local BB, DocumentRegistry, ReaderUI, Screen, UIManager
    local fixture_path = "/tmp/koreader_vertical_left_align_wrap.xhtml"
    local original_bb, original_w, original_h
    local sentence = "　お互いに（腰痛）お大事にと（勉強）頑張ってのスタンプをいくつも送り合ってトークを終了した。"

    setup(function()
        require("commonrequire")
        disable_plugins()
        local device = require("device")
        require("document/canvascontext"):init(device)
        BB = require("ffi/blitbuffer")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = device.screen
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        original_bb = Screen.bb
        original_w = Screen.screen_size.w
        original_h = Screen.screen_size.h
        Screen.bb = BB.new(1072, 1448, original_bb:getType())
        Screen.screen_size.w = 1072
        Screen.screen_size.h = 1448

        local f = assert(io.open(fixture_path, "wb"))
        f:write([[<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">
<head><meta charset="utf-8"/><style>
html { writing-mode: vertical-rl; font-family: serif-ja, serif; }
body { writing-mode: vertical-rl; line-height: 1.75; margin: 0 5pt; padding: 0; }
p { display: block; margin: 0; padding: 0; text-indent: inherit; }
</style></head><body><div><p>]], sentence, [[</p></div></body></html>]])
        f:close()
    end)

    after_each(function()
        UIManager:quit()
        UIManager._exit_code = nil
        os.remove(fixture_path)
        Screen.bb:free()
        Screen.bb = original_bb
        Screen.screen_size.w = original_w
        Screen.screen_size.h = original_h
    end)

    local function position_of(doc, text)
        local hits = doc:findAllText(text, false, 0, 10, false)
        assert.truthy(hits and hits[1], "missing search hit for " .. text)
        local y, x = doc:getScreenPositionFromXPointer(hits[1].start)
        return x, y
    end

    it("wraps the character before its draw slot crosses the clip", function()
        local reader = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(fixture_path),
        }
        UIManager:show(reader)
        reader.styletweak.book_style_tweak =
            "body, p { writing-mode: vertical-rl !important; " ..
            "text-align: left !important; text-align-last: left !important; }"
        reader.styletweak.book_style_tweak_enabled = true
        reader.styletweak:updateCssText(true)
        reader.font:onSetFontSize(31)
        reader.font:onSetLineSpace(105)
        fastforward_ui_events()
        reader.rolling:onGotoPage(1)
        fastforward_ui_events()

        local _, ta_y = position_of(reader.document, "タ")
        local n_x, n_y = position_of(reader.document, "ン")
        local pu_x, pu_y = position_of(reader.document, "プ")
        local selected = reader.document:getTextFromPositions(
            {x = Screen:getWidth() - 1, y = 0},
            {x = 0, y = Screen:getHeight() - 1}, true)

        print(string.format(
            "[vertical_left_align_wrap] タ_y=%d ン=(%d,%d) プ=(%d,%d)",
            ta_y, n_x, n_y, pu_x, pu_y))
        assert.is_true(math.abs(n_x - pu_x) < Screen:scaleBySize(31),
            "ン stayed in the overflowing column while プ wrapped")
        assert.is_true(n_y < pu_y, "ン and プ are not in reading order")
        assert.truthy(selected and selected.text:find(sentence, 1, true),
            "the full issue #74 sentence is not selectable")

        reader:onClose()
    end)
end)
