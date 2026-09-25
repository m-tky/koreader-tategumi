--[[--
Vertical inline borders next to upright fullwidth text.

Decoration and border assertions use the renderer's recorded draw rectangles,
not screen pixels.
--]]

describe("Vertical text: fullwidth inline border #vertical_fullwidth_border", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_fullwidth_border.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function begin_document(html)
        if readerui then readerui:onClose() end
        local f = assert(io.open(path, "wb"))
        f:write(html)
        f:close()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        readerui.document._document:resetVertDecorationTrace()
        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.document._document:stopVertDecorationTrace()
        local count, overflow = readerui.document._document:getVertDecorationTraceStats()
        assert.are.equal(0, overflow, "draw trace overflowed")
        local events = {}
        for i = 0, count - 1 do
            local kind, owner, character, x0, y0, x1, y1 =
                readerui.document._document:getVertDecorationTraceEvent(i)
            events[#events + 1] = {
                kind = kind, owner = owner, character = character,
                x0 = x0, y0 = y0, x1 = x1, y1 = y1,
            }
            print(string.format(
                "[vertical_fullwidth_border] kind=%d owner=%d char=U+%04X rect=(%d,%d)-(%d,%d)",
                kind, owner, character, x0, y0, x1, y1))
        end
        return events
    end

    local function decoration_for(events, kind, character)
        local found = {}
        for _, event in ipairs(events) do
            if event.kind == kind and event.character == character then
                found[#found + 1] = event
            end
        end
        assert.is_true(#found > 0,
            string.format("missing kind %d draw event for U+%04X", kind, character))
        return found
    end

    local function same_owner_x(events, kind, chars)
        local owner, x0, x1
        for _, character in ipairs(chars) do
            local matches = decoration_for(events, kind, character)
            local event
            for _, candidate in ipairs(matches) do
                if not owner or candidate.owner == owner then event = candidate; break end
            end
            assert.is_not_nil(event, string.format("missing matching owner for U+%04X", character))
            if not owner then owner, x0, x1 = event.owner, event.x0, event.x1 end
            assert.are.equal(owner, event.owner, "descendants do not share decoration owner")
            assert.are.equal(x0, event.x0, "descendant decoration x0 shifted")
            assert.are.equal(x1, event.x1, "descendant decoration x1 shifted")
        end
        return owner, x0, x1
    end
    local function underline_extent(events, owner, border)
        local intervals = {}
        for _, event in ipairs(events) do
            if event.kind == 1 and event.owner == owner then
                assert.is_true(event.x1 > event.x0 and event.y1 > event.y0,
                    "underline rectangle is empty")
                if border then
                    assert.is_true(math.min(event.x1, border.x1)
                        > math.max(event.x0, border.x0),
                        "right border does not overlap an underline")
                end
                intervals[#intervals + 1] = {event.y0, event.y1}
            end
        end
        assert.is_true(#intervals > 0, "link has no painted underline")
        table.sort(intervals, function(a, b) return a[1] < b[1] end)
        local start_y, end_y = intervals[1][1], intervals[1][2]
        for i = 2, #intervals do
            assert.is_true(intervals[i][1] <= end_y,
                "underline has a gap at a text-node boundary")
            end_y = math.max(end_y, intervals[i][2])
        end
        return start_y, end_y
    end

    it("draws an underlined bordered link without treating padding as text", function()
        local events = begin_document([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 12px; }
p { margin: 1em; }
a { border-right: 1px solid; text-decoration: underline; }
a span { font-size: 1.4em; line-height: 1.2; }
a.plain { border-right: 0; }
</style></head><body>
<p><a href="#">第<span>１</span>章</a></p>
<p><a class="plain" href="#">甲<span>２</span>乙</a></p>
</body></html>]])
        local owner = same_owner_x(events, 1, {0x7B2C, 0xFF11, 0x7AE0})
        local plain_owner = same_owner_x(events, 1, {0x7532, 0xFF12, 0x4E59})
        assert.are_not.equal(owner, plain_owner, "links unexpectedly share an owner")
        local border
        for _, event in ipairs(events) do
            if event.kind == 3 and event.owner == owner then border = event; break end
        end
        assert.is_not_nil(border, "decorated link has no painted right border")
        assert.is_true(border.x1 > border.x0 and border.y1 > border.y0,
            "right border rectangle is empty")
        local start_y, end_y = underline_extent(events, owner, border)
        underline_extent(events, plain_owner)
        for _, event in ipairs(events) do
            assert.is_false(event.kind == 3 and event.owner == plain_owner,
                "plain link unexpectedly has a right border")
        end
        assert.is_true(border.y0 <= start_y and border.y1 >= end_y,
            "right border does not span the underlined text")
    end)

    it("keeps an overline aligned across the TOC's nested font sizes", function()
        local events = begin_document([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 32px; }
p { margin: 1em; }
a { color: #000000; text-decoration: overline; }
.font-090per { font-size: 90%; }
.font-140per { font-size: 140%; }
.color-01 { color: #EE7600; }
</style></head><body>
<p><a href="#"><span class="font-090per">第</span><span class="font-140per"><span class="color-01">３</span></span><span class="font-090per">章</span></a></p>
</body></html>]])
        same_owner_x(events, 2, {0x7B2C, 0xFF13, 0x7AE0})
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
