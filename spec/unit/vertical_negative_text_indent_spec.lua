--[[--
Vertical text: negative text-indent follows the CSS inline axis.

Publishers commonly pair padding-top with an equal negative text-indent to
pull only the first formatted line into the reserved area.  The regression
used the sign of text-indent as an internal `hanging` marker, moving every
line except the first instead.  Assert on document geometry, not pixels.
--]]

describe("Vertical text: negative first-line indent #vertical_negative_indent", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local html_path = "/tmp/koreader_vertical_negative_text_indent_v2.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function fixture()
        local f = assert(io.open(html_path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 32px; }
p { margin: 0; padding-top: 5em; text-indent: 1.2em; -cr-hint: default-text-indent; }
div { margin: 0 1em; }
.outdent { text-indent: -5em; }
</style></head><body>
<div class="outdent"><p>ALPHA</p></div><div><p>BRAVO</p></div>
</body></html>]])
        f:close()
        return html_path
    end

    local function horizontal_fixture()
        local path = "/tmp/koreader_horizontal_negative_text_indent.xhtml"
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { font-size: 32px; }
p { margin: 1em 0; padding-left: 5em; text-indent: 1.2em; -cr-hint: default-text-indent; }
.outdent { text-indent: -5em; }
</style></head><body>
<div class="outdent"><p>ALPHA</p></div><div><p>BRAVO</p></div>
</body></html>]])
        f:close()
        return path
    end

    local function find_word(doc, target)
        local seen = {}
        for x = Screen:getWidth() - 4, 4, -4 do
            for y = 2, Screen:getHeight() - 2, 3 do
                local word = doc:getWordFromPosition({ x = x, y = y })
                if word and word.word == target and word.sbox then
                    local sb = word.sbox
                    local key = string.format("%d:%d:%d:%d", sb.x, sb.y, sb.w, sb.h)
                    seen[key] = { x = sb.x, y = sb.y, w = sb.w, h = sb.h }
                end
            end
        end
        local _, sb = next(seen)
        return sb
    end

    it("applies a negative length to the first formatted column only", function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(fixture()),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local alpha = assert(find_word(readerui.document, "ALPHA"), "outdented word missing")
        local bravo = assert(find_word(readerui.document, "BRAVO"), "control word missing")
        local delta = bravo.y - alpha.y
        print(string.format(
            "[vertical_negative_indent] outdent=(%d,%d %dx%d) control=(%d,%d %dx%d) delta_y=%d",
            alpha.x, alpha.y, alpha.w, alpha.h,
            bravo.x, bravo.y, bravo.w, bravo.h, delta))

        assert.is_true(delta >= 4 * 32,
            string.format("negative 5em first-line indent moved only %dpx", delta))

        readerui:onClose()
        readerui = nil
    end)

    it("uses the same signed first-line semantics in horizontal writing", function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(horizontal_fixture()),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local alpha = assert(find_word(readerui.document, "ALPHA"), "horizontal outdented word missing")
        local bravo = assert(find_word(readerui.document, "BRAVO"), "horizontal control word missing")
        local delta = bravo.x - alpha.x
        print(string.format(
            "[horizontal_negative_indent] outdent=(%d,%d %dx%d) control=(%d,%d %dx%d) delta_x=%d",
            alpha.x, alpha.y, alpha.w, alpha.h,
            bravo.x, bravo.y, bravo.w, bravo.h, delta))

        assert.is_true(delta >= 4 * 32,
            string.format("horizontal negative 5em first-line indent moved only %dpx", delta))
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
