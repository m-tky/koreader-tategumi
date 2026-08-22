--[[--
Logical sizing maps to CSS's physical height in vertical-rl: inline-size
limits top-to-bottom line advance, while block-size limits right-to-left
column advance.
--]]

describe("Vertical text: logical sizes #vertical_logical_sizes", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_logical_sizes.xhtml"

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
        for x = Screen:getWidth() - 3, 3, -3 do
            for y = 3, Screen:getHeight() - 3, 3 do
                local word = doc:getWordFromPosition({ x = x, y = y })
                if word and word.word == target and word.sbox then return word.sbox end
            end
        end
        error(target .. " was not rendered")
    end

    it("uses inline-size as the top-to-bottom available text length", function()
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body, p { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 32px; line-height: 1; }
table { inline-size: 96px; border-spacing: 0; }
td { padding: 0; }
</style></head><body><table><tr><td>甲</td><td>乙</td></tr></table></body></html>]])
        f:close()
        readerui = ReaderUI:new{ dimen = Screen:getSize(), document = DocumentRegistry:openDocument(path) }
        UIManager:show(readerui)
        fastforward_ui_events()

        local a, b = find_word(readerui.document, "甲"), find_word(readerui.document, "乙")
        local inline_extent = (b.y + b.h) - a.y
        assert.is_true(a.y < b.y, "inline-size table columns did not advance top-to-bottom")
        assert.is_true(inline_extent <= 96,
            string.format("inline-size was not applied to table width: %dpx", inline_extent))
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
