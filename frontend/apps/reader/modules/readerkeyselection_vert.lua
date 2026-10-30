-- Physical D-pad navigation for vertical-rl text. Keep horizontal selection's
-- BiDi, hyphenation and line geometry assumptions out of this path.
local VerticalSelection = {}

local function center(box)
    return box.x + box.w / 2, box.y + box.h / 2
end

local function sameColumn(a, b)
    return math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x) > math.min(a.w, b.w) / 2
end

local function wordAt(doc, xp, ending)
    if not xp then return end
    ending = ending or doc:getNextVisibleWordEnd(xp)
    if not ending then return end
    if not doc:isXPointerInCurrentPage(xp) then
        -- A word's head may be on a previous page while its tail is visible.
        -- Keep its full logical range, but only request visible fragments.
        if not doc.getCurrentPage then return end
        local page = doc:getCurrentPage()
        local count = doc.getVisiblePageCount and doc:getVisiblePageCount() or 1
        if doc:getPageFromXPointer(xp) > page + count - 1
                or doc:getPageFromXPointer(ending) < page then return end
    end
    local boxes = doc:getScreenBoxesFromPositions(xp, ending, true)
    if not boxes or #boxes == 0 then return end
    return {
        pos0 = xp,
        pos1 = ending,
        segments = boxes,
        sbox = boxes[1],
    }
end

local function adjacentPointer(doc, word, direction)
    local xp
    if direction > 0 then
        xp = doc:getNextVisibleWordStart(word.pos0)
    else
        xp = doc:getPrevVisibleWordStart(word.pos0)
    end
    if xp ~= word.pos0 then return xp end
end

-- Walk only in the requested logical direction: finish the current column,
-- find the adjacent one, then choose its closest word to the retained Y. Stop
-- at the following column instead of reconstructing every word on the page.
-- The off-page pointer is returned too, so page crossing need not scan again.
local function columnWord(doc, origin, box, direction, anchor_y, entry_box)
    local cx = center(box)
    local logical_dir = -direction
    local target_box = entry_box
    local best, best_box, best_distance
    local word, seen = origin, {}
    while word and not seen[word.pos0] do
        seen[word.pos0] = true
        local segments = word.segments or { word.sbox }
        local first, last, step = 1, #segments, 1
        if logical_dir < 0 then first, last, step = #segments, 1, -1 end
        for i = first, last, step do
            local candidate = segments[i]
            local x, y = center(candidate)
            if not target_box and not sameColumn(box, candidate) and (x - cx) * direction > 0
                    and doc:isVerticalAtPosition({ x = x, y = y }) then
                target_box = candidate
            end
            if target_box then
                if not sameColumn(target_box, candidate) then return best, best_box end
                local distance = math.abs(y - anchor_y)
                if (not best_distance or distance < best_distance)
                        and doc:isVerticalAtPosition({ x = x, y = y }) then
                    best, best_box, best_distance = word, candidate, distance
                end
            end
        end
        local xp = adjacentPointer(doc, word, logical_dir)
        if not xp or not doc:isXPointerInCurrentPage(xp) then
            return best, best_box, xp, word
        end
        word = wordAt(doc, xp)
    end
    return best, best_box
end

local function continuationPage(doc, word, direction)
    if not doc.getCurrentPage then return end
    local page = doc:getCurrentPage()
    local count = doc.getVisiblePageCount and doc:getVisiblePageCount() or 1
    if direction > 0 then
        -- An end pointer may lie exactly at the following page's start.
        local last = doc.getPrevVisibleChar and doc:getPrevVisibleChar(word.pos1) or word.pos1
        if last and doc:getPageFromXPointer(last) > page + count - 1 then
            return doc.getNextPage and doc:getNextPage(page + count - 1) or page + count
        end
    elseif doc:getPageFromXPointer(word.pos0) < page then
        return doc.getPrevPage and doc:getPrevPage(page) or page - 1
    end
end

local function crossPage(selector, word, xp, dx, dy, anchor_y)
    local doc = selector.ui.document
    local rolling = selector.ui.rolling
    if not rolling or selector.view.view_mode ~= "page" then return end
    local direction = dx ~= 0 and -dx or dy
    local continuation = continuationPage(doc, word, direction)
    if not continuation and (not xp or doc:isXPointerInCurrentPage(xp)) then return end
    local page = continuation or doc:getPageFromXPointer(xp)
    if not page or page < 1 or page > doc:getPageCount() then return end
    local old_page = doc:getCurrentPage()
    selector:clearOverlay()
    -- Do not use onGotoViewRel: its generic selector relocation would discard
    -- the retained height and interrupt an active hold selection.
    rolling:_gotoPage(page)
    local candidate = continuation and wordAt(doc, word.pos0, word.pos1) or wordAt(doc, xp)
    if not candidate then
        -- Do not leave the user on another page without a usable cursor.
        rolling:_gotoPage(old_page)
        return
    end
    local box = direction > 0 and candidate.segments[1] or candidate.segments[#candidate.segments]
    if dx ~= 0 then
        candidate, box = columnWord(doc, candidate, box, dx, anchor_y, box)
        if not candidate then
            rolling:_gotoPage(old_page)
            return
        end
    end
    rolling.xpointer = doc:getXPointer()
    return candidate, box
end

-- Shared by startup and generic page-turn relocation. A vertical word's
-- bounding box can span columns; anchor to the visible fragment nearest the
-- crosshairs instead of applying horizontal split-hyphen head/tail rules.
function VerticalSelection.anchor(selector, word)
    local doc = selector.ui.document
    if selector.ui.paging or not doc or not doc.isVerticalAtPosition then return end
    local probe = word.segments and word.segments[1] or word.sbox
    local px, py = center(probe)
    if not doc:isVerticalAtPosition({ x = px, y = py }) then return end
    local segments = doc:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
    if not segments or #segments == 0 then return end
    local x, y = center(selector._current_indicator_pos)
    local best, best_distance
    for _, segment in ipairs(segments) do
        local dx = math.max(segment.x - x, 0, x - segment.x - segment.w)
        local dy = math.max(segment.y - y, 0, y - segment.y - segment.h)
        local distance = dx * dx + dy * dy
        if not best_distance or distance < best_distance then
            best, best_distance = segment, distance
        end
    end
    word.segments = segments
    word.is_split_fragment = nil
    return center(best)
end

-- Returns false when the existing horizontal/paging selector should handle it.
function VerticalSelection.move(selector, dx, dy, quick)
    local doc = selector.ui.document
    local rect = selector._current_indicator_pos
    local x, y = center(rect)
    if not doc.isVerticalAtPosition or not doc:isVerticalAtPosition({ x = x, y = y }) then
        selector._vertical_selection_anchor_y = nil
        return false
    end
    selector._last_move_was_quick_move = quick
    selector._last_move_was_vertical = false
    selector._vertical_move_anchor_x = nil
    local word = selector._previous_indicator_word
        or doc:getWordFromPosition({ x = x, y = y }, true)
    if not word or not word.pos0 or not word.sbox then return true end
    if not word.segments and word.pos1 then
        word.segments = doc:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
    end
    -- Use the fragment under the crosshairs, not a bounding box spanning columns.
    local box = word.sbox
    for _, segment in ipairs(word.segments or {}) do
        if x >= segment.x and x <= segment.x + segment.w
                and y >= segment.y and y <= segment.y + segment.h then
            box = segment
            break
        end
    end
    if dx ~= 0 then
        selector._vertical_selection_anchor_y = selector._vertical_selection_anchor_y or y
    else
        selector._vertical_selection_anchor_y = nil
    end
    local moved = false
    local column_jump = quick and dx ~= 0
    local width = selector.view.visible_area.w
    local distance, steps, seen = 0, 0, {}
    while true do
        -- Unlike inline quick movement (four words), cross-column quick
        -- movement mirrors horizontal quick line movement: one fifth of the
        -- viewport. Accumulate distance across page boundaries as well.
        local old_x = center(box)
        local old_page = doc.getCurrentPage and doc:getCurrentPage() or 0
        local key = table.concat({ old_page, word.pos0, box.x, box.y }, ":")
        if seen[key] then break end
        seen[key] = true
        local candidate, candidate_box, next_xp, edge_word
        if dx ~= 0 then
            candidate, candidate_box, next_xp, edge_word = columnWord(doc, word, box, dx, selector._vertical_selection_anchor_y)
        else
            -- Visit physical fragments before leaving the logical word.
            for i, segment in ipairs(word.segments or { word.sbox }) do
                if segment == box then
                    candidate_box = word.segments and word.segments[i + dy]
                    if candidate_box then candidate = word end
                    break
                end
            end
            if not candidate and not continuationPage(doc, word, dy) then
                next_xp = adjacentPointer(doc, word, dy)
                candidate = wordAt(doc, next_xp)
                if candidate then
                    candidate_box = dy > 0 and candidate.segments[1] or candidate.segments[#candidate.segments]
                end
            end
        end
        if not candidate then
            candidate, candidate_box = crossPage(selector, edge_word or word, next_xp, dx, dy, selector._vertical_selection_anchor_y)
        end
        if not candidate then break end
        word, box, moved = candidate, candidate_box, true
        steps = steps + 1
        local new_x = center(box)
        local new_page = doc.getCurrentPage and doc:getCurrentPage() or 0
        if old_page ~= new_page then
            distance = distance + (dx < 0 and (old_x + width - new_x) or (width - old_x + new_x))
        else
            distance = distance + math.abs(new_x - old_x)
        end
        -- A quick move must not apply vertical logical traversal to a
        -- horizontal row. The next key event uses the horizontal selector.
        local cx, cy = center(box)
        if not doc:isVerticalAtPosition({ x = cx, y = cy }) then
            selector._vertical_selection_anchor_y = nil
            break
        end
        if column_jump then
            if distance >= width / 5 then break end
        elseif steps >= (quick and 4 or 1) then
            break
        end
    end
    if moved then
        local cx, cy = center(box)
        local target = rect:copy()
        target.x, target.y = cx - rect.w / 2, cy - rect.h / 2
        -- Do not invoke horizontal split-hyphen anchoring here.
        selector:_setIndicatorRect(target)
        word.word = word.word or doc:getTextFromXPointers(word.pos0, word.pos1)
        selector._previous_indicator_word = word
        selector._edge_dx, selector._edge_dy = nil, nil
        if selector._start_indicator_highlight then
            selector.ui.highlight:onHoldPan(nil, selector:_createHighlightGesture("hold_pan"))
        end
    else
        selector._edge_dx, selector._edge_dy = dx, dy
    end
    return true
end

return VerticalSelection
