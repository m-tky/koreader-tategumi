--[[--
Vertical text: JFM-based justification.

This checks the fork-only vertical post-pass that applies LuaTeX-ja/JFM
base glue and justify stretch/shrink to word->x. It intentionally uses sboxes
and XPointer coordinates instead of screenshot pixels so it can run in the
existing unit environment.
--]]

describe("Vertical text JFM justify #vertical_jfm_justify", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local html_path = "/tmp/koreader_vertical_jfm_justify.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    local function apply_css(readerui, text_align_last)
        readerui.styletweak.book_style_tweak =
            "body { writing-mode: vertical-rl !important; text-align: justify !important; " ..
            "text-align-last: " .. text_align_last .. " !important; } " ..
            "p, li { text-align: justify !important; }"
        readerui.styletweak.book_style_tweak_enabled = true
        readerui.styletweak:updateCssText(true)
        fastforward_ui_events()
    end

    local function ensure_html_fixture(text)
        local phrase =
            "これは縦組み本文の均等配置を確認するための長い本文です。「句読点」、中点・疑問符？！を含めても、非最終列は自然に末端まで届きます。"
        local body = {}
        for _ = 1, 180 do table.insert(body, phrase) end
        local html = [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="UTF-8"/>
<title>vertical jfm justify</title>
<style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; text-align: justify; font-family: serif; }
p { margin: 0; text-align: justify; }
</style>
</head>
<body><p>]] .. (text or table.concat(body)) .. [[</p></body>
</html>]]
        local f = assert(io.open(html_path, "wb"))
        f:write(html)
        f:close()
        return html_path
    end

    local function get_word_at(doc, x, y)
        local ok, w = pcall(function()
            return doc:getWordFromPosition({x = x, y = y})
        end)
        if ok and w and w.word and #w.word > 0 and w.sbox then return w end
        return nil
    end

    local function collect_columns(doc)
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local step_x = math.max(5, math.floor(sw / 70))
        local step_y = math.max(4, math.floor(sh / 130))
        local seen, words, em_samples = {}, {}, {}
        for x = sw - 4, 4, -step_x do
            for y = 4, sh - 4, step_y do
                local word = get_word_at(doc, x, y)
                if word then
                    local key = string.format("%d_%d_%s", word.sbox.x, word.sbox.y, word.word)
                    if not seen[key] then
                        seen[key] = true
                        table.insert(words, word)
                        if word.sbox.h >= 8 and word.sbox.h <= 80 then
                            table.insert(em_samples, word.sbox.h)
                        end
                    end
                end
            end
        end
        table.sort(em_samples)
        local em = em_samples[math.max(1, math.floor(#em_samples / 2))] or 26
        local function col_key(word)
            return math.floor((word.sbox.x + word.sbox.w / 2) / math.max(1, em))
        end
        local columns = {}
        for _, word in ipairs(words) do
            local k = col_key(word)
            local sb = word.sbox
            local c = columns[k] or {count = 0, top = math.huge, bottom = 0, x = sb.x}
            c.count = c.count + 1
            c.top = math.min(c.top, sb.y)
            c.bottom = math.max(c.bottom, sb.y + math.max(sb.h, em))
            columns[k] = c
        end
        local list = {}
        for _, c in pairs(columns) do table.insert(list, c) end
        table.sort(list, function(a, b) return a.x > b.x end)
        return list, em
    end

    local function open_reader(text)
        local path = ensure_html_fixture(text)
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        readerui.document:setFontSize(26)
        return readerui
    end

    local function positions_for(text, chars, alignment)
        local reader = open_reader(text)
        reader.styletweak.book_style_tweak =
            "body, p { writing-mode: vertical-rl !important; text-align: " .. alignment ..
            " !important; text-align-last: " .. alignment .. " !important; }"
        reader.styletweak.book_style_tweak_enabled = true
        reader.styletweak:updateCssText(true)
        fastforward_ui_events()
        reader.rolling:onGotoPage(1)
        fastforward_ui_events()
        local positions = {}
        for _, char in ipairs(chars) do
            local hits = reader.document:findAllText(char, false, 0, 10, false)
            assert.truthy(hits and hits[1], "missing search hit for " .. char)
            local y, x = reader.document:getScreenPositionFromXPointer(hits[1].start)
            positions[#positions + 1] = {x = x, y = y}
        end
        positions.bottom = Screen:getHeight() - reader.document:getPageMargins().bottom
        reader:onClose()
        UIManager:quit()
        UIManager._exit_code = nil
        return positions
    end

    it("distributes body fallback evenly in final and non-final columns", function()
        local chars = {"天", "地", "玄", "黄", "宇", "宙", "洪", "荒"}
        local text = table.concat(chars)
        for _, sample in ipairs({text, text:rep(100)}) do
            local ragged = positions_for(sample, chars, "left")
            local justified = positions_for(sample, chars, "justify")
            local min_extra, max_extra = math.huge, 0
            for i = 2, #chars do
                assert.equals(justified[1].x, justified[i].x, "sample should stay in one column")
                local extra = (justified[i].y - justified[i-1].y) - (ragged[i].y - ragged[i-1].y)
                assert.truthy(extra >= 0, "body spacing must not shrink")
                min_extra = math.min(min_extra, extra)
                max_extra = math.max(max_extra, extra)
            end
            assert.truthy(max_extra - min_extra <= 1, "rounding must be balanced within one pixel")
            if sample == text then
                assert.equals(justified.bottom, justified[#chars].y + 26,
                    "explicitly justified final column must reach the bottom")
                local total_extra = (justified[#chars].y - justified[1].y)
                    - (ragged[#chars].y - ragged[1].y)
                for i = 2, #chars do
                    local cumulative_extra = (justified[i].y - justified[1].y)
                        - (ragged[i].y - ragged[1].y)
                    assert.equals(math.floor((i-1) * total_extra / (#chars-1)), cumulative_extra,
                        "fractional pixels must carry across the column")
                end
            end
        end
    end)

    it("keeps Japanese-Western boundary spacing fixed", function()
        local chars = {"天", "A", "地", "B", "玄", "C", "黄"}
        local text = table.concat(chars)
        local ragged = positions_for(text, chars, "left")
        local justified = positions_for(text, chars, "justify")
        for i = 2, #chars do
            assert.equals(justified[1].x, justified[i].x)
            assert.equals(ragged[i].y - ragged[i-1].y, justified[i].y - justified[i-1].y,
                "Japanese-Western spacing changed at " .. chars[i])
        end
    end)

    it("uses punctuation capacity before balanced body fallback", function()
        local chars = {"天", "地", "玄", "黄", "、", "宇", "宙", "洪", "荒"}
        local text = table.concat(chars)
        local ragged = positions_for(text, chars, "left")
        local justified = positions_for(text, chars, "justify")
        local min_extra, max_extra = math.huge, 0
        for i = 2, #chars do
            assert.equals(justified[1].x, justified[i].x, "short text should stay in one column")
            local extra = (justified[i].y - justified[i-1].y) - (ragged[i].y - ragged[i-1].y)
            if i == 6 then
                assert.equals(math.floor(26 / 4), extra, "comma capacity must be used in full first")
            elseif i == 5 then
                assert.equals(0, extra, "spacing before a comma must not expand")
            else
                assert.truthy(extra > 0, "remaining space must reach body boundaries")
                min_extra = math.min(min_extra, extra)
                max_extra = math.max(max_extra, extra)
            end
        end
        assert.truthy(max_extra - min_extra <= 1, "body fallback must be balanced")
        assert.equals(justified.bottom, justified[#chars].y + 26)
    end)

    it("does not expand body spacing when punctuation alone can fill the column", function()
        local chars = {"天", "地", "玄", "黄", "、", "宇", "宙", "洪", "荒"}
        local text = table.concat(chars)
        local initial = positions_for(text, chars, "left")
        local shortfall = initial.bottom - (initial[#chars].y + 26)
        local original_bb, original_height = Screen.bb, Screen.screen_size.h
        local height = original_height - shortfall + 3
        Screen.bb = require("ffi/blitbuffer").new(Screen:getWidth(), height, original_bb:getType())
        Screen.screen_size.h = height
        local ok, err = pcall(function()
            local ragged, remaining
            -- Footer margins depend on the viewport height, so calibrate with
            -- actual document coordinates instead of assuming a fixed margin.
            for _ = 1, 4 do
                ragged = positions_for(text, chars, "left")
                remaining = ragged.bottom - (ragged[#chars].y + 26)
                if remaining > 0 and remaining <= math.floor(26 / 4) then break end
                height = height - (remaining - 3)
                Screen.bb:free()
                Screen.bb = require("ffi/blitbuffer").new(Screen:getWidth(), height, original_bb:getType())
                Screen.screen_size.h = height
            end
            assert.truthy(remaining > 0 and remaining <= math.floor(26 / 4))
            local justified = positions_for(text, chars, "justify")
            for i = 2, #chars do
                assert.equals(justified[1].x, justified[i].x)
                local extra = (justified[i].y - justified[i-1].y) - (ragged[i].y - ragged[i-1].y)
                assert.equals(i == 6 and remaining or 0, extra,
                    "punctuation must absorb the small remainder without body expansion")
            end
            assert.equals(justified.bottom, justified[#chars].y + 26)
        end)
        Screen.bb:free()
        Screen.bb, Screen.screen_size.h = original_bb, original_height
        assert.truthy(ok, err)
    end)

    it("keeps text-align-last:auto ragged but allows text-align-last:justify", function()
        local function last_column_shortfall(text_align_last)
            local readerui = open_reader()
            if not readerui then return nil end
            apply_css(readerui, text_align_last)
            readerui.rolling:onGotoPage(readerui.document:getPageCount())
            fastforward_ui_events()
            local columns = collect_columns(readerui.document)
            readerui:onClose()
            UIManager:quit()
            if #columns < 2 then return nil end
            local page_bottom = 0
            for _, c in ipairs(columns) do page_bottom = math.max(page_bottom, c.bottom) end
            table.sort(columns, function(a, b) return a.count < b.count end)
            return page_bottom - columns[1].bottom
        end
        local auto_shortfall = last_column_shortfall("auto")
        local justify_shortfall = last_column_shortfall("justify")
        if not auto_shortfall or not justify_shortfall then
            pending("not enough columns on final page")
            return
        end
        print(string.format("[vertical_jfm_justify] text-align-last auto=%d justify=%d",
            auto_shortfall, justify_shortfall))
        assert.truthy(auto_shortfall > justify_shortfall + 4,
            string.format("auto=%d justify=%d", auto_shortfall, justify_shortfall))
    end)
end)
