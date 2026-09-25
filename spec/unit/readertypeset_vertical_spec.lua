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
        assert.is_truthy(menu_items.document_settings.sub_item_table[1].help_text:find("horizontal reading", 1, true))
    end)

    it("warns after enabling vertical reading, but not when disabling", function()
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local shown_message
        local after_open_callback
        local typeset = setmetatable({
            vertical_reading = false,
            ui = {
                doc_settings = { saveSetting = function() end },
                reloadDocument = function(_, _, _, callback)
                    after_open_callback = callback
                end,
            },
        }, { __index = ReaderTypeset })

        UIManager.show = function(_, message)
            shown_message = message
        end
        local ok, err = pcall(function()
            assert.is_true(typeset:onToggleVerticalReading(true))
            assert.is_function(after_open_callback)
            after_open_callback()
            assert.is_truthy(shown_message.text:find("horizontal reading", 1, true))
            assert.are.equal(5, shown_message.timeout)
            assert.are.equal("notice-warning", shown_message.icon)

            after_open_callback = nil
            typeset:onToggleVerticalReading(false)
            assert.is_nil(after_open_callback)
        end)
        UIManager.show = original_show
        assert.is_true(ok, err)
    end)

end)
