--[[--
Vertical text: column-bottom completeness test.

The specific bug:
  After the TTB m_advance fix (accurate per-char advances), processParagraphVertical
  may fit one more character into a column.  The OLD vert_skip_draw condition
  `y0 + descent > clip.bottom` can fire for this last character when:
    y0 = clip.top + (n-1)*font_size   (last char's screen Y)
    descent = font->getHeight() - font->getBaseline()   (≈ 4–6px)
    clip.bottom - clip.top = m_pageHeight
    (n-1)*font_size + descent > m_pageHeight
  This happens when m_pageHeight mod font_size < descent.

  The character IS in the frmline (getWordFromPosition finds it), but its
  pixels are absent from Screen.bb.

Test strategy:
  1. Find words near the column bottom.
  2. For each such word, verify that Screen.bb has ink pixels in its sbox.
     "In frmline but no pixels" = phantom = bug.
  3. Also directly test the vert_skip_draw edge case:
     Create a scenario where y0 is just below clip.bottom - descent and assert
     the character is still rendered.

Run via:
  ./kodev test front -f "column bottom"
--]]

describe("Vertical column bottom", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    local epub_candidates = {
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
        "spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub",
    }
    local epub_path
    for _, p in ipairs(epub_candidates) do
        local f = io.open(p, "r")
        if f then f:close(); epub_path = p; break end
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function apply_vertical_css(readerui)
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak =
                "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
    end

    local function get_word_at(doc, x, y)
        local ok, w = pcall(function()
            return doc:getWordFromPosition({x=x, y=y})
        end)
        if ok and w and w.word and #w.word > 0 then return w end
        return nil
    end

    local function sbox_has_ink(sb, threshold)
        threshold = threshold or 180
        local bb = Screen.bb
        if not bb then return false end
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local x0 = math.max(0, sb.x)
        local y0 = math.max(0, sb.y)
        local x1 = math.min(sw - 1, sb.x + sb.w - 1)
        local y1 = math.min(sh - 1, sb.y + sb.h - 1)
        if x0 > x1 or y0 > y1 then return false end
        for y = y0, y1 do
            for x = x0, x1 do
                local ok, px = pcall(function() return bb:getPixel(x, y) end)
                if ok and px and px:getR() < threshold then return true end
            end
        end
        return false
    end

    -- -----------------------------------------------------------------------

    describe("no missing char at column bottom #column_bottom", function()
        local readerui, doc

        setup(function()
            if not epub_path then return end
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
        end)

        teardown(function()
            if readerui then readerui:onClose() end
        end)

        before_each(function()
            if not readerui then return end
            UIManager:show(readerui)
            apply_vertical_css(readerui)
        end)

        after_each(function()
            UIManager:quit()
        end)

        -- ----------------------------------------------------------------
        -- Core phantom test: every word in the lower column area must
        -- have ink pixels at its sbox.
        -- ----------------------------------------------------------------
        it("every word near column bottom has ink pixels at its sbox #column_bottom", function()
            if not epub_path then pending("no epub available"); return end

            local w = Screen:getWidth()
            local h = Screen:getHeight()

            local em, page_used
            for try_page = 2, math.min(readerui.document:getPageCount(), 12) do
                readerui.rolling:onGotoPage(try_page)
                fastforward_ui_events()
                doc = readerui.document
                for ty = math.floor(h * 0.3), math.floor(h * 0.7), 12 do
                    for tx = math.floor(w * 0.1), math.floor(w * 0.9), 20 do
                        local word = get_word_at(doc, tx, ty)
                        if word and word.sbox and word.sbox.h > 4 then
                            em = word.sbox.h; break
                        end
                    end
                    if em then break end
                end
                if em then page_used = try_page; break end
            end
            assert.truthy(em and em > 4, "No em size found")

            local mid_y = math.floor(h * 0.40)
            local col_xs = {}
            local prev_x = -1
            for tx = w - 5, 5, -3 do
                local word = get_word_at(doc, tx, mid_y)
                if word and word.sbox then
                    local col_x = word.sbox.x + math.floor(word.sbox.w / 2)
                    if math.abs(col_x - prev_x) > math.floor(em * 0.8) then
                        table.insert(col_xs, col_x)
                        prev_x = col_x
                    end
                end
            end

            print(string.format("[col_bottom] page=%d em=%d cols=%d h=%d",
                page_used, em, #col_xs, h))

            if #col_xs < 1 then
                pending("No columns found")
                return
            end

            local checked, phantoms = 0, {}
            for _, cx in ipairs(col_xs) do
                local y_lo = math.floor(h * 0.55)
                local y_hi = math.floor(h * 0.90)
                local step = math.max(3, math.floor(em / 4))
                local ty = y_hi
                while ty >= y_lo do
                    local word = get_word_at(doc, cx, ty)
                    if word and word.sbox and word.sbox.h > 0 then
                        checked = checked + 1
                        if not sbox_has_ink(word.sbox) then
                            table.insert(phantoms, string.format(
                                "cx=%d ty=%d word='%s' sbox={%d,%d,%d,%d} NO INK",
                                cx, ty, word.word or "?",
                                word.sbox.x, word.sbox.y, word.sbox.w, word.sbox.h))
                        end
                        ty = ty - em + step
                    else
                        ty = ty - step
                    end
                end
            end

            print(string.format("[col_bottom] checked=%d phantoms=%d",
                checked, #phantoms))

            assert.truthy(checked > 0, "No words sampled — column/page setup issue")
            assert.equals(0, #phantoms,
                #phantoms .. " phantom word(s):\n  "
                .. table.concat(phantoms, "\n  "))
        end)

        -- ----------------------------------------------------------------
        -- Edge-case: search across multiple pages for a column whose
        -- last word's sbox.y + sbox.h is very close to the page bottom.
        -- That word MUST have ink (vert_skip_draw must not fire for it).
        -- ----------------------------------------------------------------
        it("word at column bottom edge (near clip.bottom) has ink pixels #column_bottom", function()
            if not epub_path then pending("no epub available"); return end

            local w = Screen:getWidth()
            local h = Screen:getHeight()

            -- Search multiple pages for a word whose bottom edge is within
            -- 4px of the page bottom — these are the candidates most likely
            -- to be affected by the old descent-based vert_skip_draw.
            local found_edge_word = nil
            local found_page = nil

            for try_page = 2, math.min(readerui.document:getPageCount(), 20) do
                readerui.rolling:onGotoPage(try_page)
                fastforward_ui_events()
                doc = readerui.document

                local near_bottom_y = h - 30   -- sample near the bottom
                local step = 4

                for tx = w - 5, 5, -step do
                    local word = get_word_at(doc, tx, near_bottom_y)
                    if word and word.sbox and word.sbox.h > 4 then
                        -- Check if this word's bottom is very close to page bottom
                        local sbox_bottom = word.sbox.y + word.sbox.h
                        if sbox_bottom > h - 25 and sbox_bottom < h then
                            found_edge_word = word
                            found_page = try_page
                            break
                        end
                    end
                end
                if found_edge_word then break end
            end

            if not found_edge_word then
                -- If no edge word found, at minimum verify no phantom in normal range
                pending("No edge word (close to page bottom) found on pages 2–20")
                return
            end

            print(string.format(
                "[col_bottom edge] page=%d word='%s' sbox.y=%d sbox.h=%d bottom=%d h=%d",
                found_page, found_edge_word.word or "?",
                found_edge_word.sbox.y, found_edge_word.sbox.h,
                found_edge_word.sbox.y + found_edge_word.sbox.h, h))

            assert.truthy(sbox_has_ink(found_edge_word.sbox),
                string.format(
                    "Word '%s' at sbox {y=%d,h=%d} (bottom=%d, h=%d) has NO ink pixels — "
                    .. "vert_skip_draw incorrectly prevented rendering",
                    found_edge_word.word or "?",
                    found_edge_word.sbox.y, found_edge_word.sbox.h,
                    found_edge_word.sbox.y + found_edge_word.sbox.h, h))
        end)
    end)

    it("hangs a column-end ideographic full stop into the bottom margin #column_bottom", function()
        local path = "/tmp/koreader_vertical_period_column_end.xhtml"
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 15px; line-height: 1; padding-top: 3px; }
p { margin: 0; padding: 0; }
span { color: #808080; }
</style></head><body>]])
        local expected_periods = 11
        for count = 45, 55 do
            f:write("<p>", string.rep("一", count),
                "<span>。</span>二</p>")
        end
        f:write([[</body></html>]])
        f:close()

        local period_reader = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(period_reader)
        fastforward_ui_events()
        period_reader.typography:onToggleFloatingPunctuation(true)
        fastforward_ui_events()
        local margins = assert(period_reader.document:getPageMargins())
        local content_bottom = Screen:getHeight() - margins.bottom
        local overflow_ink = 0
        -- getWordFromPosition() intentionally excludes the page margin, so the
        -- exactly aligned period cannot be counted semantically. Its authored
        -- mid-gray lets us verify its ink directly in the first few margin rows,
        -- above the reader footer.
        local overflow_bottom = math.min(Screen:getHeight() - 1,
            content_bottom + math.min(10, margins.bottom - 1))
        for y = content_bottom, overflow_bottom do
            for x = 3, Screen:getWidth() - 3 do
                local px = Screen.bb:getPixel(x, y)
                if px and px:getR() >= 80 and px:getR() <= 190 then
                    overflow_ink = overflow_ink + 1
                end
            end
        end

        local periods = {}
        local width, height = Screen:getWidth(), Screen:getHeight()
        for x = width - 3, 3, -3 do
            for y = 3, height - 3, 3 do
                local word = get_word_at(period_reader.document, x, y)
                if word and word.sbox and word.word:sub(-#"。") == "。" then
                    local key = string.format("%d:%d:%d:%d", word.sbox.x,
                        word.sbox.y, word.sbox.w, word.sbox.h)
                    periods[key] = word.sbox
                end
            end
        end

        local function has_period_ink(box)
            -- The semantic word box includes the preceding ideograph. The period is
            -- the final half-em JFM slot, so inspect only that slot. Its
            -- authored mid-gray also separates it from the black 十 even when
            -- the emulator framebuffer itself is grayscale.
            local slot = math.max(1, math.ceil(box.w / 2))
            for y = box.y + box.h - slot, box.y + box.h - 1 do
                for x = box.x, box.x + box.w - 1 do
                    local px = Screen.bb:getPixel(x, y)
                    if px and px:getR() >= 80 and px:getR() <= 190 then
                        return true
                    end
                end
            end
            return false
        end

        local found, near_bottom, phantoms, bottom_boxes = 0, 0, {}, {}
        for _, box in pairs(periods) do
            found = found + 1
            if box.y + box.h >= height - 40 then
                near_bottom = near_bottom + 1
                table.insert(bottom_boxes, string.format("{%d,%d,%d,%d}",
                    box.x, box.y, box.w, box.h))
            end
            if not has_period_ink(box) then
                table.insert(phantoms, string.format("{%d,%d,%d,%d}",
                    box.x, box.y, box.w, box.h))
            end
        end
        print(string.format(
            "[col_bottom period] in_content=%d/%d overflow_ink=%d near_bottom=%d boxes=%s phantoms=%s",
            found, expected_periods, overflow_ink, near_bottom,
            table.concat(bottom_boxes, ","), table.concat(phantoms, ",")))

        period_reader:onClose()
        UIManager:quit()
        assert.are.equal(expected_periods - 1, found,
            "exactly one ideographic full stop should hang outside the content clip")
        assert.is_true(overflow_ink >= 3,
            "the hanging ideographic full stop has no ink in the bottom margin")
        assert.is_true(near_bottom > 0,
            "fixture did not place an ideographic full stop near a column end")
        assert.are.same({}, phantoms,
            "ideographic full stop had a selectable box but no painted glyph")
    end)
end)
