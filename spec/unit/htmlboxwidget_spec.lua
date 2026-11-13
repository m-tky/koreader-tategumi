describe("HtmlBoxWidget module", function()
    local HtmlBoxWidget, Geom

    setup(function()
        require("commonrequire")
        HtmlBoxWidget = require("ui/widget/htmlboxwidget")
        Geom = require("ui/geometry")
    end)

    local function new_widget(body)
        local widget = HtmlBoxWidget:new{
            dimen = Geom:new{ x = 0, y = 0, w = 400, h = 200 },
        }
        widget:setContent(body, nil, 20)
        return widget
    end

    -- Select the whole first line the same way the hold gestures do: the text
    -- is built from the word boxes MuPDF laid out.
    local function select_first_line(widget)
        -- page_boxes are only collected once a hold starts.
        widget:onHoldStartText(nil, { pos = { x = 0, y = 0 } })
        local line = widget.page_boxes[1]
        local y = (line.y0 + line.y1) / 2
        local first_word, last_word = line[1], line[#line]

        local selected_text
        widget:onHoldStartText(nil, { pos = { x = first_word.x0 + 1, y = y } })
        widget:onHoldReleaseText(function(text) selected_text = text end,
            { pos = { x = last_word.x1 - 1, y = y } })
        return selected_text
    end

    it("should not put spaces between adjacent CJK characters", function()
        local widget = new_widget("<p>倉庫</p>")
        assert.is.same("倉庫", select_first_line(widget))
    end)

    it("should keep separating english words with a space", function()
        local widget = new_widget("<p>hello world</p>")
        assert.is.same("hello world", select_first_line(widget))
    end)
end)
