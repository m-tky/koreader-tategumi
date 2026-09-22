describe("ReaderTypeset vertical reading", function()
    local ReaderTypeset

    setup(function()
        require("commonrequire")
        ReaderTypeset = require("apps/reader/modules/readertypeset")
    end)

    local function new_typeset(tweak_css)
        return setmetatable({
            ui = {
                styletweak = {
                    getCssText = function() return tweak_css end,
                },
            },
            genStyleSheetMenu = function() return {} end,
        }, { __index = ReaderTypeset })
    end

    it("appends vertical layout CSS without discarding style tweaks", function()
        local typeset = new_typeset("p { text-align: justify; }")
        typeset.vertical_reading = true

        local css = typeset:getAppendedStyleSheet()

        assert.is_truthy(css:find("p { text%-align: justify; }"))
        assert.is_truthy(css:find("writing%-mode: vertical%-rl !important;"))
        assert.is_truthy(css:find("text%-orientation: mixed !important;"))
    end)

    it("leaves style tweaks unchanged when vertical reading is disabled", function()
        local typeset = new_typeset("body { font-family: serif; }")
        typeset.vertical_reading = false

        assert.are.equal("body { font-family: serif; }", typeset:getAppendedStyleSheet())
    end)

    it("adds the toggle under Document settings", function()
        local typeset = new_typeset("")
        local menu_items = {
            document_settings = { sub_item_table = {} },
        }

        typeset:addToMainMenu(menu_items)

        assert.are.equal(1, #menu_items.document_settings.sub_item_table)
        assert.are.equal("Vertical reading", menu_items.document_settings.sub_item_table[1].text)
    end)
end)
