-- JFM expands effective advances after the common alignment pass. End and
-- center alignment must use that final width, rather than clipping the last
-- glyphs at the bottom of a vertical column.
describe("Vertical text: final inline alignment #vertical_end_alignment", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local reader
    local path = "/tmp/koreader_vertical_end_alignment.xhtml"
    local text = "──著者名『縦書きの引用文』"

    setup(function()
        require("commonrequire")
        disable_plugins()
        local device = require("device")
        require("document/canvascontext"):init(device)
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = device.screen
        UIManager = require("ui/uimanager")
    end)

    after_each(function()
        if reader then reader:onClose(); reader = nil end
        UIManager:quit()
        os.remove(path)
    end)

    for _, alignment in ipairs({"right", "center"}) do
        it("keeps " .. alignment .. "-aligned JFM text inside its inline extent", function()
            local f = assert(io.open(path, "wb"))
            f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja"><head><style>
html, body { writing-mode: vertical-rl; margin: 0; padding: 0; }
p { font-size: 32px; margin: 5.55556em 0 1em; text-align: ]], alignment, [[; }
</style></head><body><p>]], text, [[</p><p style="text-align: left">]],
                text, [[</p></body></html>]])
            f:close()
            reader = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(path),
            }
            UIManager:show(reader)
            fastforward_ui_events()

            local doc = reader.document
            local hits = doc:findAllText(text, false, 0, 10, false)
            assert.truthy(hits and hits[1], "aligned text is missing")
            local boxes = doc:getScreenBoxesFromPositions(hits[1].start, hits[1]["end"], true)
            assert.truthy(boxes and boxes[1], "aligned text has no screen geometry")
            local top, bottom = math.huge, 0
            for _, box in ipairs(boxes) do
                top = math.min(top, box.y)
                bottom = math.max(bottom, box.y + box.h)
            end
            local margins = doc:getPageMargins()
            local inline_end = Screen:getHeight() - margins.bottom
            print(string.format("[vertical_end_alignment] align=%s top=%d bottom=%d end=%d",
                alignment, top, bottom, inline_end))
            assert.is_true(bottom <= inline_end + 1, "JFM text exceeds the bottom of the column")
            assert.truthy(hits[2], "start-aligned control is missing")
            local control = doc:getScreenBoxesFromPositions(hits[2].start, hits[2]["end"], true)
            assert.truthy(control and control[1], "control has no screen geometry")
            local inline_start, control_end = math.huge, 0
            for _, box in ipairs(control) do
                inline_start = math.min(inline_start, box.y)
                control_end = math.max(control_end, box.y + box.h)
            end
            -- Screen boxes are cropped to the viewport, so a clipped final
            -- glyph can masquerade as a correctly end-aligned column.
            assert.is_true(math.abs((bottom - top) - (control_end - inline_start)) <= 2,
                "aligned text is shorter than the unclipped control")
            if alignment == "right" then
                assert.is_true(math.abs(bottom - inline_end) <= 2,
                    "end-aligned text does not reach the column end")
            else
                assert.is_true(math.abs((top - inline_start) - (inline_end - bottom)) <= 2,
                    "center-aligned text has unequal inline gaps")
            end
        end)
    end
end)
