--[[--
Vertical text: verify columns start at the screen top (no staircase).

With CSSLogical, CSS padding-left on containers maps to block-direction
(screen-X), not inline-direction (screen-Y).  All body paragraphs get
y_base = clip.top regardless of HTML nesting depth.

Test: find words very close to the screen top (y ≤ clip.top + 1 char).
Such words should exist in EVERY column (columns fill from screen top).
If some columns have no words near the top, those columns start lower —
which indicates a staircase / y_base mismatch.
--]]

describe("Vertical text: column top alignment (no staircase)", function()
    local epub_path
    for _, p in ipairs({
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
        "spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub",
    }) do
        local f = io.open(p, "r")
        if f then f:close(); epub_path = p; break end
    end

    local DocumentRegistry, ReaderUI, Screen, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    local readerui
    before_each(function()
        if not epub_path then return end
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        UIManager:show(readerui)
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak = "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
    end)

    after_each(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
    end)

    it("columns contain words near screen top (no staircase) #column_top", function()
        if not epub_path then pending("no epub"); return end

        local doc = readerui.document
        local w = Screen:getWidth()

        -- Find a page with text then scan for the topmost word in each column
        local found_near_top = 0
        local total_cols_checked = 0

        for try_page = 2, math.min(doc:getPageCount(), 6) do
            readerui.rolling:onGotoPage(try_page)
            fastforward_ui_events()

            -- Sample across columns (x-axis), look for words near screen top (y ≈ 20-50)
            -- A word within 50px of top means that column starts near top
            for tx = w - 10, 20, -26 do
                -- Check three y-levels near the screen top
                for ty = 20, 60, 10 do
                    local word = doc:getWordFromPosition({x=tx, y=ty})
                    if word and word.sbox and word.sbox.h > 8 then
                        found_near_top = found_near_top + 1
                        break
                    end
                end
                total_cols_checked = total_cols_checked + 1
            end
            if total_cols_checked >= 20 then break end
        end

        print(string.format("[column_top] cols_checked=%d  cols_with_word_near_top=%d  ratio=%.0f%%",
            total_cols_checked, found_near_top, found_near_top/total_cols_checked*100))

        -- Most columns (>60%) should have words near the screen top.
        -- With a large staircase, some columns start at y=90+ and have nothing near top.
        local ratio = found_near_top / total_cols_checked
        assert.is_true(ratio > 0.6,
            string.format("Only %.0f%% of columns have words near screen top — staircase suspected", ratio*100))
    end)
end)
