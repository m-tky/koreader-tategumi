--[[--
Vertical text: multi-em glyph column break (no clip / no overflow).

In vertical-rl, some glyphs occupy more than one em of column depth: 2em
nibu-dashi / double-em dash composites, vform leaders, and the vertical
kana-repeat marks 〱 (U+3031) / 〲 (U+3032).  processParagraphVertical must
break BEFORE the column bottom when the next item is such a multi-em glyph,
otherwise the glyph is drawn past clip.bottom and gets clipped (mikire), or
skipped entirely (phantom).

The root-cause column-fill rewrite (issue #17) folded the former
self_multiem_extra into the single col_used_est estimate: a multi-em item now
contributes its real advance (adv_delta), which already exceeds one em.  This
spec guards that path against regression.

Method (the user's idea): make the WHOLE document multi-em (a long run of
〱〲, each confirmed 2em).  Then nearly every column ends on the multi-em
boundary case, so a broken break decision is certain to clip at least one
glyph.  We assert every rendered kana-repeat glyph has ink across its full
sbox (a clipped or phantom glyph loses ink in its lower half).

Run via:
  ./kodev test front -f "multi-em"
--]]

describe("Vertical text: multi-em glyph column break #multiem", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/multiem_test.epub"
    -- 2em vertical kana-repeat marks that fill the fixture.
    local MULTIEM = { ["〱"] = true, ["〲"] = true }

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    local function get_word_at(doc, x, y)
        local ok, w = pcall(function()
            return doc:getWordFromPosition({x = x, y = y})
        end)
        if ok and w and w.word and #w.word > 0 and w.sbox then return w end
        return nil
    end

    -- True if the given screen rectangle contains any dark (ink) pixel.
    local function rect_has_ink(x, y, w, h, threshold)
        threshold = threshold or 180
        local bb = Screen.bb
        if not bb then return false end
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local x0, y0 = math.max(0, x), math.max(0, y)
        local x1, y1 = math.min(sw - 1, x + w - 1), math.min(sh - 1, y + h - 1)
        if x0 > x1 or y0 > y1 then return false end
        for yy = y0, y1 do
            for xx = x0, x1 do
                local ok, px = pcall(function() return bb:getPixel(xx, yy) end)
                if ok and px and px:getR() < threshold then return true end
            end
        end
        return false
    end

    it("every multi-em kana-repeat glyph is fully drawn (no column-bottom clip) #multiem", function()
        local f = io.open(epub_path, "r")
        if not f then pending("multiem_test.epub not found"); return end
        f:close()

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        UIManager:show(readerui)
        local doc = readerui.document
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak =
                "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        doc:setFontSize(26)
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()

        local w, h = Screen:getWidth(), Screen:getHeight()
        local step_x = math.max(6, math.floor(w / 50))
        local step_y = math.max(4, math.floor(h / 120))

        local seen, glyphs = {}, {}
        for x = w - 4, 4, -step_x do
            for y = 4, h - 4, step_y do
                local word = get_word_at(doc, x, y)
                if word and MULTIEM[word.word] then
                    local key = string.format("%d_%d", word.sbox.x, word.sbox.y)
                    if not seen[key] then
                        seen[key] = true
                        table.insert(glyphs, word)
                    end
                end
            end
        end

        if #glyphs < 5 then
            pending("too few multi-em glyphs rendered (" .. #glyphs .. ")")
            return
        end

        -- Confirm these really are multi-em (sbox depth ≈ 2em, clearly taller
        -- than a single em ≈ font size 26).
        local tall = 0
        for _, g in ipairs(glyphs) do
            if g.sbox.h >= 40 then tall = tall + 1 end
        end
        assert.truthy(tall > 0,
            "no glyph has a multi-em (≥40px) sbox depth — fixture/font not producing 2em marks")

        -- Each glyph must have ink in BOTH halves of its sbox.  A glyph clipped
        -- at the column bottom keeps its top but loses its lower half; a phantom
        -- (vert_skip_draw) has no ink at all.
        local clipped = {}
        for _, g in ipairs(glyphs) do
            local sb = g.sbox
            local half = math.floor(sb.h / 2)
            local top_ink = rect_has_ink(sb.x, sb.y, sb.w, half)
            local bot_ink = rect_has_ink(sb.x, sb.y + half, sb.w, sb.h - half)
            if not (top_ink and bot_ink) then
                table.insert(clipped, string.format(
                    "glyph '%s' sbox={%d,%d,%d,%d} top_ink=%s bot_ink=%s",
                    g.word, sb.x, sb.y, sb.w, sb.h, tostring(top_ink), tostring(bot_ink)))
            end
        end

        print(string.format("[multiem] glyphs=%d tall=%d clipped=%d",
            #glyphs, tall, #clipped))

        readerui:onClose()
        UIManager:quit()

        assert.equals(0, #clipped,
            #clipped .. " multi-em glyph(s) clipped/phantom at column bottom:\n  "
            .. table.concat(clipped, "\n  "))
    end)
end)
