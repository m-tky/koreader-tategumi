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
    local DocumentRegistry, DocSettings, ReaderUI, UIManager, Screen
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
        DocSettings = require("docsettings")
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

        before_each(function()
            if not epub_path then return end
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
            UIManager:show(readerui)
            apply_vertical_css(readerui)
        end)

        after_each(function()
            if readerui then
                readerui:onClose()
                readerui = nil
            end
            UIManager:quit()
            UIManager._exit_code = nil
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

    it("renders a boundary-crossing full stop outside the regular clip #column_bottom", function()
        local function write_fixture(path, padding_top)
            local f = assert(io.open(path, "wb"))
            f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 15px; line-height: 1; padding-top: ]],
                padding_top, [[px; }
p { margin: 0; padding: 0; line-height: 700px; }
</style></head><body>]])
            -- The oversized line-height makes the column cross the page's left
            -- clip. Varying the top padding over one 15px em finds the layout
            -- where the following stop starts exactly at clip.bottom.
            f:write("<p>", string.rep("一", 49), "。二</p>")
            f:write([[</body></html>]])
            f:close()
        end

        local function write_screenshot_fixture(path)
            local f = assert(io.open(path, "wb"))
            f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 15px; line-height: 1; padding-top: 3px; }
p { margin: 0; padding: 0; }
</style></head><body>]])
            local repeated_text =
                "これは縦書きのぶら下げ表示を確認するために同じ文を続けて配置した長い文章です"
            local final_text =
                "最後の句点だけを段の外へぶら下げて表示するために文字数を調整します"
            local extra_char = os.getenv("KOREADER_HANGING_EXTRA_CHAR") and "字" or ""
            f:write("<p>", string.rep(repeated_text, 7), final_text,
                extra_char, "。</p>")
            f:write([[</body></html>]])
            f:close()
        end

        local attempt_count, recovery_count, reject_count, draw_count, layout_count
        local font_entry_count, outside_regular_count, active_clip_count
        local regular_bottom, active_bottom, glyph_top, glyph_bottom
        local observed_attempt_count = 0
        local matched_padding
        for padding_top = 0, 14 do
            -- A unique path prevents an emulator-opened copy of the manual
            -- fixture (and its cached document settings) from affecting this
            -- layout probe.
            local tmp_base = os.tmpname()
            os.remove(tmp_base)
            local path = tmp_base .. ".xhtml"
            write_fixture(path, padding_top)

            local period_reader = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(path),
            }
            UIManager:show(period_reader)
            fastforward_ui_events()
            -- Make the disabled-to-enabled transition explicit so a saved
            -- default cannot move the diagnostic draw before the reset.
            period_reader.typography:onToggleFloatingPunctuation(false)
            fastforward_ui_events()
            period_reader.document._document:resetVertExactHangingClip()
            period_reader.typography:onToggleFloatingPunctuation(true)
            fastforward_ui_events()
            attempt_count, recovery_count, reject_count, draw_count, layout_count =
                period_reader.document._document:getVertExactHangingClip()
            font_entry_count, outside_regular_count, active_clip_count,
                regular_bottom, active_bottom, glyph_top, glyph_bottom =
                period_reader.document._document:getVertExactHangingGlyph()
            observed_attempt_count = observed_attempt_count + attempt_count

            period_reader:onClose()
            UIManager:quit()
            UIManager._exit_code = nil
            DocSettings.updateLocation(path)
            os.remove(path)
            -- A boundary-crossing stop that used the line-wide overflow clip is not the
            -- case under test; keep looking for a per-word recovery (or for a
            -- rejection, which is what the broken implementation reports).
            if recovery_count > 0 or reject_count > 0 then
                matched_padding = padding_top
                break
            end
        end

        local screenshot_path = os.getenv("KOREADER_HANGING_SCREENSHOT")
        if recovery_count > 0 then
            local tmp_base = os.tmpname()
            os.remove(tmp_base)
            local path = tmp_base .. ".xhtml"
            write_screenshot_fixture(path)
            local screenshot_reader = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(path),
            }
            UIManager:show(screenshot_reader)
            fastforward_ui_events()
            screenshot_reader.typography:onToggleFloatingPunctuation(false)
            fastforward_ui_events()
            screenshot_reader.document._document:resetVertExactHangingClip()
            screenshot_reader.typography:onToggleFloatingPunctuation(true)
            fastforward_ui_events()
            local sa, sr, sj, sd, sl =
                screenshot_reader.document._document:getVertExactHangingClip()
            local sfe, sor, sac, srb, sab, sgt, sgb =
                screenshot_reader.document._document:getVertExactHangingGlyph()
            if screenshot_path then
                Screen:shot(screenshot_path)
                print("[col_bottom hanging] screenshot=" .. screenshot_path)
            end
            print(string.format(
                "[col_bottom hanging screenshot] layout_hang=%d exact_attempt=%d clip_recovery=%d clip_reject=%d font_entry=%d glyph_draw=%d outside_regular=%d inside_active_clip=%d regular_bottom=%d glyph_y=%d..%d active_bottom=%d",
                sl, sa, sr, sj, sfe, sd, sor, sac, srb, sgt, sgb, sab))
            if not os.getenv("KOREADER_HANGING_EXTRA_CHAR") then
                assert.is_true(sl > 0,
                    "the long paragraph did not lay out its final stop as hanging punctuation")
                assert.is_true(sa > 0,
                    "the long paragraph's boundary-crossing stop was not recognized while drawing")
                assert.is_true(sd > 0,
                    "the long paragraph's hanging stop did not submit a glyph bitmap")
                assert.is_true(sor > 0 and sgb > srb,
                    "the long paragraph's hanging stop did not render beyond the regular clip")
                assert.are.equal(sd, sac,
                    "the long paragraph's hanging glyph was clipped by the active overflow clip")
                assert.is_true(sgb <= sab,
                    "the long paragraph's hanging glyph exceeded the active overflow clip")
            end
            screenshot_reader:onClose()
            UIManager:quit()
            UIManager._exit_code = nil
            DocSettings.updateLocation(path)
            os.remove(path)
        end
        print(string.format(
            "[col_bottom hanging] padding_top=%s layout_hang=%d exact_attempt=%d clip_recovery=%d clip_reject=%d font_entry=%d glyph_draw=%d outside_regular=%d inside_active_clip=%d regular_bottom=%d glyph_y=%d..%d active_bottom=%d",
            matched_padding or "none", layout_count, observed_attempt_count,
            recovery_count, reject_count, font_entry_count, draw_count,
            outside_regular_count, active_clip_count, regular_bottom,
            glyph_top, glyph_bottom, active_bottom))

        assert.is_true(observed_attempt_count > 0,
            "no top padding within one em produced a boundary-crossing hanging punctuation draw")
        assert.is_true(recovery_count > 0,
            "fixture did not exercise per-word recovery from the active clip")
        assert.are.equal(0, reject_count,
            "a boundary-crossing hanging punctuation remained outside the active draw clip")
        assert.is_true(draw_count > 0,
            "the recovered hanging punctuation did not submit a glyph bitmap")
        assert.is_true(outside_regular_count > 0,
            "the test glyph did not render beyond the regular content clip")
        assert.is_true(glyph_bottom > regular_bottom,
            "the test glyph rectangle did not cross the regular content clip bottom")
        assert.are.equal(draw_count, active_clip_count,
            "the hanging glyph bitmap was clipped by the expanded active clip")
        assert.is_true(glyph_bottom <= active_bottom,
            "the hanging glyph extended beyond the expanded active clip")
    end)
end)
