--[[--
Vertical text: logical inline insets.

In vertical-rl the inline axis runs from physical top to bottom, so logical
inline margins, padding and borders must reserve space before and after an
inline element.
--]]

describe("Vertical text: logical inline insets #vertical_inline_insets", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_inline_insets.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function find_word(doc, target)
        local found
        for x = Screen:getWidth() - 3, 3, -3 do
            for y = 3, Screen:getHeight() - 3, 3 do
                local word = doc:getWordFromPosition({ x = x, y = y })
                if word and word.word == target and word.sbox then
                    found = word.sbox
                end
            end
        end
        return assert(found, target .. " was not rendered")
    end

    it("maps logical margins, padding and borders onto the vertical inline axis", function()
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body, p { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 32px; line-height: 1; }
span { margin-inline-start: 1em; margin-inline-end: 1em;
       padding-inline-start: 0.5em; padding-inline-end: 0.5em;
       border-inline: 4px solid; }
</style></head><body><p>甲<span>乙</span>丙</p></body></html>]])
        f:close()

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local first = find_word(readerui.document, "甲")
        local middle = find_word(readerui.document, "乙")
        local last = find_word(readerui.document, "丙")
        local before = middle.y - (first.y + first.h)
        local after = last.y - (middle.y + middle.h)
        print(string.format("[vertical_inline_insets] before=%d after=%d", before, after))
        assert.is_true(before >= 40, "logical inline-start inset did not reserve vertical space")
        assert.is_true(after >= 40, "logical inline-end inset did not reserve vertical space")
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
