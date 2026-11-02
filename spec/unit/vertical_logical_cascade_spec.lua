-- Logical sides must use the final cascaded writing mode, not the mode that
-- happened to be available when the declaration was parsed or applied.
describe("Vertical text: logical property cascade #vertical_logical_cascade", function()
    local Registry, ReaderUI, Screen, UIManager, DocSettings

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        Registry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        DocSettings = require("docsettings")
    end)

    local function render(label, rules, inline)
        local path = os.tmpname()
        os.remove(path)
        path = path .. ".xhtml"
        local reader
        local cleaned = false
        local function cleanup()
            if cleaned then return end
            cleaned = true
            if reader then reader:onClose() end
            UIManager:quit()
            UIManager._exit_code = nil
            DocSettings:open(path):purge()
            os.remove(path)
        end
        finally(cleanup)
        local f = assert(io.open(path, "wb"))
        f:write([[<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
            html, body, p { margin: 0; padding: 0; border: 0; }
            body { font-size: 32px; line-height: 1; }
            ]], rules, [[</style></head><body><p style="]], inline or "", [[">甲乙丙</p></body></html>]])
        f:close()
        reader = ReaderUI:new{ dimen = Screen:getSize(), document = Registry:openDocument(path) }
        UIManager:show(reader)
        fastforward_ui_events()
        local hits = reader.document:findAllText("甲", false, 0, 10, false)
        assert.truthy(hits and hits[1], label .. ": missing fixture character")
        local boxes = reader.document:getScreenBoxesFromPositions(hits[1].start, hits[1]["end"], true)
        assert.truthy(boxes and boxes[1], label .. ": missing character box")
        assert.equals(1, #boxes, label .. ": character must have a single box")
        local box = boxes[1]
        assert.is_true(box.w > 0 and box.h > 0, label .. ": empty character box")
        cleanup()
        return box
    end

    local baselines = {}
    local function baseline(mode)
        if not baselines[mode] then
            baselines[mode] = render(mode .. " baseline", "p { writing-mode: " .. mode .. "; }")
        end
        return baselines[mode]
    end

    local function shifted(label, box, control, dx, dy)
        assert.equals(dx, box.x - control.x, label .. ": wrong physical X inset")
        assert.equals(dy, box.y - control.y, label .. ": wrong physical Y inset")
        assert.equals(control.w, box.w, label .. ": character width changed")
        assert.equals(control.h, box.h, label .. ": character height changed")
    end

    -- Padding exercises the shared cascade machinery; margin and border below
    -- only need targeted cases for their separate physical-side storage.
    it("maps padding against the final writing-mode cascade", function()
        local control = baseline("vertical-rl")
        local cases = {
            { name = "physical control", rules = "p { writing-mode: vertical-rl; padding-top: 60px; }" },
            { name = "mode before property", rules = "p { writing-mode: vertical-rl; padding-inline-start: 60px; }" },
            { name = "mode after property", rules = "p { padding-inline-start: 60px; writing-mode: vertical-rl; }" },
            { name = "mode round trip across rules", rules = "p { writing-mode: vertical-rl; padding-inline-start: 20px; } " ..
                "p { writing-mode: horizontal-tb; padding-inline-start: 60px; } p { writing-mode: vertical-rl; }" },
            { name = "inherited parent mode", rules = "p { padding-inline-start: 60px; } body { writing-mode: vertical-rl; }" },
            { name = "inline property inherits mode", rules = "body { writing-mode: vertical-rl; }",
                inline = "padding-inline-start: 60px;" },
            { name = "inline mode wins cascade", rules = "p { writing-mode: horizontal-tb; padding-inline-start: 60px; }",
                inline = "writing-mode: vertical-rl;" },
        }
        for _, case in ipairs(cases) do
            shifted(case.name, render(case.name, case.rules, case.inline), control, 0, 60)
        end
    end)

    it("preserves physical/logical order and importance", function()
        local control = baseline("vertical-rl")
        local logical = "padding-inline-start: 60px"
        local physical = "padding-top: 20px"
        local cases = {
            { name = "later physical", declarations = logical .. "; " .. physical .. ";", amount = 20 },
            { name = "later logical", declarations = physical .. "; " .. logical .. ";", amount = 60 },
            { name = "important logical", declarations = logical .. " !important; " .. physical .. ";", amount = 60 },
            { name = "important physical", declarations = physical .. " !important; " .. logical .. ";", amount = 20 },
            { name = "both important later physical", declarations = logical .. " !important; " .. physical .. " !important;",
                amount = 20 },
            { name = "both important later logical", declarations = physical .. " !important; " .. logical .. " !important;",
                amount = 60 },
            { name = "stylesheet important beats inline", declarations = logical .. " !important;",
                inline = physical .. ";", amount = 60 },
            { name = "inline important beats stylesheet", declarations = physical .. " !important;",
                inline = logical .. " !important;", amount = 60 },
        }
        for _, case in ipairs(cases) do
            local box = render(case.name, "body { writing-mode: vertical-rl; } p { " .. case.declarations .. " }", case.inline)
            shifted(case.name, box, control, 0, case.amount)
        end
    end)

    for _, property in ipairs({
        { name = "margin", value = "60px", amount = 60, other = "20px", other_amount = 20 },
        { name = "border", value = "8px solid black", amount = 8, other = "3px solid black", other_amount = 3 },
    }) do
        it("maps " .. property.name .. " sides without losing physical precedence", function()
            local control = baseline("vertical-rl")
            local logical = property.name .. "-inline-start: " .. property.value .. ";"
            local physical = property.name .. "-top: " .. property.other
            local cases = {
                { name = "later mode", rules = "p { writing-mode: horizontal-tb; " .. logical ..
                    " } p { writing-mode: vertical-rl; }", amount = property.amount },
                { name = "inline inherited mode", rules = "body { writing-mode: vertical-rl; }",
                    inline = logical, amount = property.amount },
                { name = "important physical", rules = "body { writing-mode: vertical-rl; } p { " ..
                    physical .. " !important; " .. logical .. " }", amount = property.other_amount },
                { name = "both important later logical", rules = "body { writing-mode: vertical-rl; } p { " ..
                    physical .. " !important; " .. property.name .. "-inline-start: " .. property.value ..
                    " !important; }", amount = property.amount },
            }
            for _, case in ipairs(cases) do
                local label = property.name .. " " .. case.name
                shifted(label, render(label, case.rules, case.inline), control, 0, case.amount)
            end
        end)
    end

    it("uses the final horizontal mode and keeps physical/logical source order", function()
        local control = baseline("horizontal-tb")
        for _, case in ipairs({
            { name = "horizontal later physical", declarations = "padding-inline-start: 60px; padding-left: 20px;", amount = 20 },
            { name = "horizontal later logical", declarations = "padding-left: 20px; padding-inline-start: 60px;", amount = 60 },
        }) do
            local box = render(case.name, "p { writing-mode: vertical-rl; " .. case.declarations ..
                " } p { writing-mode: horizontal-tb; }")
            shifted(case.name, box, control, case.amount, 0)
        end
    end)

    it("resolves generated inline content's logical padding against its final mode", function()
        local prefix = 'p::before { content: "丁"; '
        local suffix = "} p { writing-mode: vertical-rl; }"
        local control = render("generated content baseline", prefix .. suffix)
        local physical = render("generated content physical control", prefix .. "padding-top: 60px; " .. suffix)
        shifted("generated content physical control", physical, control, 0, 60)
        local logical = render("generated content later mode", prefix ..
            "writing-mode: horizontal-tb; padding-inline-start: 60px; } " ..
            "p::before { writing-mode: vertical-rl; " .. suffix)
        shifted("generated content later mode", logical, control, 0, 60)
    end)
end)
