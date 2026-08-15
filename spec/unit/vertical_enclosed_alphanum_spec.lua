--[[--
Regression spec: Enclosed Alphanumerics (U+2460-24FF, e.g. ①②③) in
vertical-rl mode.

Before the vertical Enclosed Alphanumerics fix, these chars fell into
word_is_latin_in_vertical (render+rotate path). Symptoms:
  - The rotated buffer (width = font_h > em) overflowed the column right
    edge by (font_h - em) / 2 px, clipping the glyph on the rightmost
    column (visible on PW2 / 212 DPI devices).

The fix is deliberately applied only in vertical layout: classifying these
characters as CJK globally would change word segmentation and line breaking
for horizontal documents. This spec checks their vertical rendering while
preserving the normal multi-character word-selection behavior.

Run via:
  ./kodev test front -f "Enclosed alphanumeric"
--]]

describe("Enclosed alphanumeric vertical text", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/enclosed_alphanum.epub"

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
            readerui.styletweak.book_style_tweak = "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
    end

    -- Find the first tap position whose word equals `target` (single-char match).
    -- Returns x, y, word or nil if none found across the probe grid.
    local function find_word(doc, target)
        local h = Screen:getHeight()
        local w = Screen:getWidth()
        local y_step = math.max(8, math.floor(h / 60))
        local x_step = math.max(6, math.floor(w / 40))
        for y = math.floor(h * 0.05), math.floor(h * 0.95), y_step do
            for x = w - 4, 4, -x_step do
                local ok, word = pcall(function()
                    return doc:getWordFromPosition({x=x, y=y})
                end)
                if ok and word and word.word == target then
                    return x, y, word
                end
            end
        end
        return nil
    end

    local function find_word_containing(doc, target)
        local h = Screen:getHeight()
        local w = Screen:getWidth()
        local y_step = math.max(8, math.floor(h / 60))
        local x_step = math.max(6, math.floor(w / 40))
        for y = math.floor(h * 0.05), math.floor(h * 0.95), y_step do
            for x = w - 4, 4, -x_step do
                local ok, word = pcall(function()
                    return doc:getWordFromPosition({x=x, y=y})
                end)
                if ok and word and word.word and word.word:find(target, 1, true) then
                    return x, y, word
                end
            end
        end
        return nil
    end

    local readerui, doc

    setup(function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
    end)

    teardown(function()
        readerui:onClose()
    end)

    before_each(function()
        UIManager:show(readerui)
        apply_vertical_css(readerui)
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()
        doc = readerui.document
    end)

    after_each(function()
        UIManager:quit()
    end)

    it("detects vertical-rl mode", function()
        assert.is_true(doc:isVerticalText(),
            "fixture must render in vertical-rl mode")
    end)

    it("U+2460 (①) is selectable as a single-char word", function()
        -- Less discriminating: a single ① between CJK chars is its own word
        -- even without the fix (CJK neighbours act as word separators).
        -- The discriminating case lives in the next test.
        local x, y, word = find_word(doc, "①")
        assert.truthy(word,
            "no tap position returned word=\"①\" — Enclosed Alphanumerics "
            .. "may not be classified as CJK (lStr_isCJK regression?)")
        assert.equals("①", word.word)
    end)

    it("U+2466 (⑦) preserves horizontal word segmentation", function()
        -- Enclosed Alphanumerics are treated specially only during vertical
        -- drawing. Their selection semantics remain unchanged so horizontal
        -- documents do not acquire new CJK word boundaries.
        local x, y, word = find_word_containing(doc, "⑦")
        assert.truthy(word,
            "no tap position returned word=\"⑦\" — Enclosed Alphanumerics "
            .. "could not be found in the circled-number run")
        assert.equals("⑥⑦⑧⑨⑩", word.word)
    end)

    it("U+2460 sbox fits within its em column (no right-edge overflow)", function()
        -- After the fix the ① glyph is drawn via the JFM vertical path
        -- (LFNT_HINT_IS_VERTICAL), keeping the bitmap within the em-square
        -- column.  Before the fix it was drawn via render+rotate with a
        -- font_h-wide buffer that overflowed the column right edge by
        -- (font_h - em) / 2 px.
        --
        -- Observable: the ① sbox.w (column width) must match the body
        -- strut width to within ±1 px.  Scan the page to determine the
        -- body strut as the mode of sbox.w in the body-column range.
        local h = Screen:getHeight()
        local w = Screen:getWidth()
        local freq = {}
        for _, yf in ipairs({0.25, 0.4, 0.55, 0.7}) do
            local y = math.floor(h * yf)
            local step = math.max(5, math.floor(w / 30))
            for x = w - 4, 4, -step do
                local ok, word = pcall(function()
                    return doc:getWordFromPosition({x=x, y=y})
                end)
                if ok and word and word.sbox then
                    local sw = word.sbox.w
                    if sw >= 15 and sw <= 80 then
                        freq[sw] = (freq[sw] or 0) + 1
                    end
                end
            end
        end
        local strut, best = 0, 0
        for w_val, cnt in pairs(freq) do
            if cnt > best then best = cnt; strut = w_val end
        end
        if strut == 0 then pending("could not determine strut"); return end

        local x, y, word = find_word(doc, "①")
        if not word then pending("① not found"); return end
        local sb = word.sbox
        assert.truthy(math.abs(sb.w - strut) <= 1,
            string.format(
                "①.sbox.w=%d differs from body strut=%d by >1 px — "
                .. "circled number is in a wider column (render+rotate regression)",
                sb.w, strut))
        -- Right edge must not exceed the page right margin (which is
        -- effectively at Screen:getWidth() minus right page margin).  We
        -- only check that sbox does not extend past the screen edge plus
        -- a small tolerance for sub-pixel rendering.
        assert.truthy(sb.x + sb.w <= w + 2,
            string.format(
                "①.sbox right edge (%d) exceeds screen width (%d) — "
                .. "rotated buffer overflowed the rightmost column",
                sb.x + sb.w, w))
    end)
end)
