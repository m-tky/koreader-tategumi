--[[--
Vertical text: mixed CJK/Latin column fill (no premature break).

Regression test for issue #17 (m-tky/koreader-tategumi): in vertical-rl, a
column that mixes CJK with Latin/foreign words broke *early*, leaving several
em of empty space at the column bottom, because the column-fill estimate in
processParagraphVertical counted every char as one em — over-counting the
narrow Latin glyphs (≈ em/3) and the half-em JFM punctuation.  The fix makes
that estimate mirror the real rendered depth (col_used_est).

This is the *under-fill* direction.  The opposite failure (a glyph drawn past
the column bottom / clipped) is covered by vertical_column_bottom_spec; Latin
words being split mid-word is covered by vertical_latin_split_spec.

Strategy (no screenshot pixel measurement — uses engine sboxes only):
  1. Render page 1 of latin_split_test.epub in vertical-rl.
  2. page_fill_bottom = the deepest column bottom on the page.  At least one
     pure-CJK column fills completely, so this is the effective clip.bottom.
  3. For every column that contains a Latin target word ("Nachbild",
     "Geschehen", ...), all of which sit mid-paragraph in this fixture, the
     column must fill to within a small margin of page_fill_bottom.  A
     premature break leaves it several em short.

Run via:
  ./kodev test front -f "column fill"
--]]

describe("Vertical text: mixed CJK/Latin column fill #column_fill", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/latin_split_test.epub"
    -- Latin words that appear only mid-paragraph in the fixture (never at a
    -- paragraph end), so their column is expected to be full.
    local target_words = { "Nachbild", "Geschehen", "Theatron", "Proske" }

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

    it("columns containing Latin words fill to the column bottom #column_fill", function()
        local f = io.open(epub_path, "r")
        if not f then pending("latin_split_test.epub not found"); return end
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
        local step_y = math.max(4, math.floor(h / 90))

        -- Sweep the page collecting unique words (keyed by sbox position).
        local seen, words = {}, {}
        local em_samples = {}
        for x = w - 4, 4, -step_x do
            for y = 4, h - 4, step_y do
                local word = get_word_at(doc, x, y)
                if word then
                    local key = string.format("%d_%d", word.sbox.x, word.sbox.y)
                    if not seen[key] then
                        seen[key] = true
                        table.insert(words, word)
                        if word.sbox.h > 4 then table.insert(em_samples, word.sbox.h) end
                    end
                end
            end
        end

        if #words == 0 then pending("no words found on page"); return end
        table.sort(em_samples)
        local em = em_samples[math.max(1, math.floor(#em_samples / 2))] or 26

        -- Effective bottom of the text area = deepest any column reaches.
        local page_fill_bottom = 0
        for _, word in ipairs(words) do
            page_fill_bottom = math.max(page_fill_bottom, word.sbox.y + word.sbox.h)
        end

        -- Deepest fill per column (bucketed by sbox x-centre, ~em wide).
        local function col_key(word)
            return math.floor((word.sbox.x + word.sbox.w / 2) / math.max(1, em))
        end
        local col_bottom = {}
        for _, word in ipairs(words) do
            local k = col_key(word)
            col_bottom[k] = math.max(col_bottom[k] or 0, word.sbox.y + word.sbox.h)
        end

        -- For each Latin target word, its column must fill to near the bottom.
        local target_set = {}
        for _, t in ipairs(target_words) do target_set[t] = true end

        local violations = {}
        local checked = 0
        local tolerance = math.floor(em * 2.5)  -- allow up to ~2.5em of legitimate slack
        for _, word in ipairs(words) do
            if target_set[word.word] then
                local cb = col_bottom[col_key(word)] or 0
                local shortfall = page_fill_bottom - cb
                checked = checked + 1
                print(string.format(
                    "[column_fill] word='%s' col_bottom=%d page_bottom=%d shortfall=%d (%.1fem) em=%d",
                    word.word, cb, page_fill_bottom, shortfall, shortfall / em, em))
                if shortfall > tolerance then
                    table.insert(violations, string.format(
                        "'%s' column %d short of page bottom %d by %dpx (%.1fem)",
                        word.word, cb, page_fill_bottom, shortfall, shortfall / em))
                end
            end
        end

        readerui:onClose()
        UIManager:quit()

        if checked == 0 then
            pending("no Latin target words found on page 1")
            return
        end
        assert.equals(0, #violations,
            #violations .. " prematurely-broken mixed column(s) (issue #17):\n  "
            .. table.concat(violations, "\n  "))
    end)
end)
