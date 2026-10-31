-- Compare the ink aspect ratio of isolated glyphs, using a bundled font and
-- a horizontal control. Absolute sbox fill ratios vary with font bearings.
describe("Vertical rotation #rotation", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
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

    local function close_document()
        if readerui then readerui:onClose(); readerui = nil end
        UIManager:quit()
        UIManager._exit_code = nil
        if path then os.remove(path); path = nil end
    end
    after_each(close_document)

    local function glyph_ink(character, mode)
        path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja"><head><style>
html, body { margin: 0; padding: 0; writing-mode: ]], mode, [[; }
p { margin: 0; padding: 0; font-family: "Noto Sans CJK SC"; }
</style></head><body><p>]], character, [[</p></body></html>]])
        f:close()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        local doc = readerui.document
        doc:setFontFace("Noto Sans CJK SC")
        doc:setFontSize(48)
        doc:setVisiblePageCount(1)
        readerui.rolling:onUpdatePos()
        fastforward_ui_events()
        assert.equals(mode == "vertical-rl", doc:isVerticalText())
        local hits = doc:findAllText(character, false, 0, 10, false)
        assert.truthy(hits and hits[1], "rotation glyph is missing")
        local boxes = doc:getScreenBoxesFromPositions(hits[1].start, hits[1]["end"], true)
        assert.truthy(boxes and boxes[1], "rotation glyph has no screen rectangle")
        assert.equals(1, #boxes, "isolated glyph must occupy one rectangle")
        local box = boxes[1]
        local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
        for y = math.max(0, box.y), math.min(Screen:getHeight() - 1, box.y + box.h - 1) do
            for x = math.max(0, box.x), math.min(Screen:getWidth() - 1, box.x + box.w - 1) do
                if Screen.bb:getPixel(x, y):getR() < 180 then
                    min_x, max_x = math.min(min_x, x), math.max(max_x, x)
                    min_y, max_y = math.min(min_y, y), math.max(max_y, y)
                end
            end
        end
        assert.is_true(max_x >= min_x, "rotation glyph has no rendered ink")
        local width, height = max_x - min_x + 1, max_y - min_y + 1
        close_document()
        return width, height
    end

    for _, character in ipairs({"ー", "…"}) do
        it("renders " .. character .. " vertically rather than horizontally", function()
            local hw, hh = glyph_ink(character, "horizontal-tb")
            local vw, vh = glyph_ink(character, "vertical-rl")
            assert.is_true(hw > hh * 2,
                string.format("horizontal control ink is %dx%d, expected a wide glyph", hw, hh))
            assert.is_true(vh > vw * 2,
                string.format("vertical ink is %dx%d, expected a tall glyph (control %dx%d)", vw, vh, hw, hh))
        end)
    end
end)
