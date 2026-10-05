--[[--
Page progression direction detector for automatic RTL/LTR reading order.

Supports:
- EPUB: reads `page-progression-direction` from OPF spine directly via the
  ZIP archive (bypasses crengine cache entirely — reliable on first open)
- CBZ/CBR/CBT: reads the standard `<Manga>YesAndRightToLeft</Manga>` value
  from ComicInfo.xml, with `<ReadingDirection>` accepted for compatibility

Both formats are handled via ffi/archiver (libarchive), so no C++ changes
are required and the detection is cache-independent.
]]

local logger = require("logger")
local M = {}

-- ── helpers ──────────────────────────────────────────────────────────────

local function openArchiveReader(filepath)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok then return nil end
    local reader = Archiver.Reader:new()
    if not reader:open(filepath) then return nil end
    return reader
end

-- ── ComicInfo.xml (CBZ/CBR) ──────────────────────────────────────────────

local function elementValue(xml, name)
    -- ComicInfo normally has unprefixed elements under a root carrying xmlns
    -- declarations. Also accept explicitly prefixed elements and attributes,
    -- while avoiding similarly named elements such as <MangaFoo>.
    local boundary = "%f[%s>/]"
    local value = xml:match("<%s*" .. name .. boundary .. "[^>]*>(.-)</%s*" .. name .. "%s*>")
    if not value then
        value = xml:match("<%s*[%w_.-]+:" .. name .. boundary
            .. "[^>]*>(.-)</%s*[%w_.-]+:" .. name .. "%s*>")
    end
    return value
end

local function canonicalValue(value)
    if not value then return nil end
    -- Enum values are ASCII. Ignoring separators makes the compatibility
    -- field tolerant of the forms found in existing comic libraries.
    return value:lower():gsub("[%s_-]", "")
end

function M.parseComicInfo(xml)
    if not xml then return nil end
    xml = xml:gsub("^\239\187\191", "", 1)
             :gsub("<!%-%-.-%-%->", "")

    -- ComicInfo 1.x/2.x defines this as the RTL-reading manga value. It is
    -- authoritative when present; the non-RTL Manga enum values do not by
    -- themselves specify a page direction.
    local manga = canonicalValue(elementValue(xml, "Manga"))
    if manga == "yesandrighttoleft" then
        return "rtl"
    end

    -- ReadingDirection is not part of the core ComicInfo schema, but is used
    -- by some producers and by older versions of this fork.
    local direction = canonicalValue(elementValue(xml, "ReadingDirection"))
    if direction == "rtl" or direction == "righttoleft" then
        return "rtl"
    elseif direction == "ltr" or direction == "lefttoright" then
        return "ltr"
    end
    return nil
end

local function directionFromComicInfo(filepath)
    local reader = openArchiveReader(filepath)
    if not reader then return nil end
    local direction
    local comicinfo_path
    for entry in reader:iterate() do
        if entry.mode == "file" then
            local lp = entry.path:lower()
            if lp == "comicinfo.xml" or lp:match("/comicinfo%.xml$") then
                comicinfo_path = entry.path
                direction = M.parseComicInfo(reader:extractToMemory(entry.path))
                break
            end
        end
    end
    reader:close()
    logger.dbg("PageDirection: ComicInfo", filepath, comicinfo_path, "→", direction)
    return direction
end

-- ── EPUB OPF ─────────────────────────────────────────────────────────────

-- Read only the metadata start tags we need; tolerate namespace prefixes,
-- both XML quote styles and whitespace around '='. Ignore commented-out tags.
local function tagAttribute(xml, element, attribute)
    if not xml then return nil end
    xml = xml:gsub("<!%[CDATA%[.-%]%]>", ""):gsub("<!%-%-.-%-%->", "")
    local cursor = 1
    while true do
        local _, name_end, name = xml:find("<%s*([%w_.:-]+)", cursor)
        if not name then return nil end
        local tag_end = name_end
        -- A '>' inside a quoted value does not end the start tag.
        while true do
            local pos, _, delimiter = xml:find("([>'\"])", tag_end + 1)
            if not pos then return nil end
            tag_end = pos
            if delimiter == ">" then break end
            tag_end = xml:find(delimiter, pos + 1, true)
            if not tag_end then return nil end
        end
        cursor = tag_end + 1
        if (name:match("([^:]+)$")) == element then
            local attrs = xml:sub(name_end + 1, tag_end - 1)
            for key, _, value in attrs:gmatch("([%w_.:-]+)%s*=%s*(['\"])(.-)%2") do
                if key == attribute then
                    return require("util").htmlEntitiesToUtf8(value)
                end
            end
        end
    end
end

local function opfPathFromContainer(xml)
    return tagAttribute(xml, "rootfile", "full-path")
end

local function ppdFromOPF(xml)
    local ppd = tagAttribute(xml, "spine", "page-progression-direction")
    if not ppd then return nil end
    ppd = ppd:lower()
    return (ppd == "rtl" or ppd == "ltr") and ppd or nil
end

local function directionFromEpub(filepath)
    local reader = openArchiveReader(filepath)
    if not reader then return nil end

    -- Step 1: find container.xml to locate the OPF.
    local opf_path
    for entry in reader:iterate() do
        if entry.mode == "file" then
            local lp = entry.path:lower()
            if lp == "meta-inf/container.xml" then
                local xml = reader:extractToMemory(entry.path)
                opf_path = opfPathFromContainer(xml)
                break
            end
        end
    end
    if not opf_path then
        reader:close()
        logger.dbg("PageDirection: no container.xml found in", filepath)
        return nil
    end

    -- Step 2: read the OPF and extract page-progression-direction.
    local direction
    -- extractToMemory can seek; try by path key first.
    local xml = reader:extractToMemory(opf_path)
    if not xml then
        -- Path lookup may be case-sensitive; scan all entries.
        local lp_target = opf_path:lower()
        for entry in reader:iterate() do
            if entry.mode == "file" and entry.path:lower() == lp_target then
                xml = reader:extractToMemory(entry.path)
                break
            end
        end
    end
    direction = ppdFromOPF(xml)
    reader:close()
    logger.dbg("PageDirection: EPUB", filepath, "→", direction)
    return direction
end

-- ── public API ───────────────────────────────────────────────────────────

-- Return the page progression direction for a document file.
-- @param document  A document instance (must expose .file path).
-- @return "rtl", "ltr", or nil (direction unknown / not specified).
function M.getDirection(document)
    if not document or not document.file then return nil end
    local ext = document.file:match("%.(%w+)$")
    if not ext then return nil end
    ext = ext:lower()

    if ext == "epub" or ext == "epub3" then
        return directionFromEpub(document.file)
    elseif ext == "cbz" or ext == "cbr" or ext == "cbt" then
        return directionFromComicInfo(document.file)
    end

    return nil
end

return M
