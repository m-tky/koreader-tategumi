-- A narrow cover must still occupy its own page in vertical EPUBs. Ordinary
-- image-only spine items must retain their ability to share a page with text.
describe("Vertical text: cover page isolation #vertical_cover_page", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local reader, path

    setup(function()
        require("commonrequire")
        disable_plugins()
        local device = require("device")
        require("document/canvascontext"):init(device)
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = device.screen
        UIManager = require("ui/uimanager")
    end)

    after_each(function()
        if reader then reader:onClose(); reader = nil end
        UIManager:quit()
        if path then os.remove(path); path = nil end
    end)

    local function fixture(svg_wrapper, declared_cover)
        path = os.tmpname()
        os.remove(path)
        path = path .. ".epub"
        local writer = require("ffi/archiver").Writer:new()
        assert.is_true(writer:open(path, "zip"))
        local function add(name, content)
            assert.is_true(writer:addFileFromMemory(name, content))
        end
        add("mimetype", "application/epub+zip")
        add("META-INF/container.xml", [[<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>]])
        add("book.opf", [[<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">vertical-cover-]] ..
            tostring(svg_wrapper) .. "-" .. tostring(declared_cover) .. [[</dc:identifier>
<dc:title>Cover regression</dc:title><dc:language>ja</dc:language>
<meta name="primary-writing-mode" content="vertical-rl"/><meta name="cover" content="cover"/></metadata>
<manifest><item id="cover" href="]] .. (declared_cover and "cover.svg" or "other.svg") .. [[" media-type="image/svg+xml"/>
<item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>
<item id="title" href="title.xhtml" media-type="application/xhtml+xml"/>
<item id="figure" href="figure.xhtml" media-type="application/xhtml+xml"/>
<item id="text" href="text.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine page-progression-direction="rtl"><itemref idref="front"/><itemref idref="title"/>
<itemref idref="figure"/><itemref idref="text"/></spine></package>]])
        local image = [[<svg xmlns="http://www.w3.org/2000/svg" width="180" height="400" viewBox="0 0 180 400">
<rect width="180" height="400" fill="black"/></svg>]]
        add("cover.svg", image)
        add("other.svg", image)
        local function html(content)
            return [[<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
body { margin: 0; padding: 0; } p { margin: 0; }
</style></head><body>]] .. content .. "</body></html>"
        end
        local cover = '<img src="cover.svg" width="180" height="400"/>'
        if svg_wrapper then
            cover = [[<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
width="180" height="400" viewBox="0 0 180 400"><image xlink:href="cover.svg" width="180" height="400"/></svg>]]
        end
        add("front.xhtml", html("<div>" .. cover .. "</div>"))
        add("title.xhtml", html("<p>COVERTITLE</p>"))
        add("figure.xhtml", html('<img src="other.svg" width="60" height="100"/>'))
        add("text.xhtml", html("<p>AFTERFIGURE</p>"))
        writer:close()
        return path
    end

    local function page_of(doc, text)
        local hits = doc:findAllText(text, false, 0, 10, false)
        assert.truthy(hits and hits[1], "missing text: " .. text)
        return doc:getPageFromXPointer(hits[1].start)
    end

    for _, case in ipairs({
        { name = "SVG-wrapped cover", svg = true, cover = true, page = 2 },
        { name = "img cover", svg = false, cover = true, page = 2 },
        { name = "non-cover opening image", svg = true, cover = false, page = 1 },
    }) do
        it("preserves page flow for an " .. case.name, function()
            reader = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(fixture(case.svg, case.cover)),
            }
            UIManager:show(reader)
            fastforward_ui_events()
            local title_page = page_of(reader.document, "COVERTITLE")
            local text_page = page_of(reader.document, "AFTERFIGURE")
            print(string.format("[vertical_cover_page] case=%s title=%d after_figure=%d",
                case.name, title_page, text_page))
            assert.are.equal(case.page, title_page,
                "cover boundary was lost or introduced a blank page")
            if case.cover then
                local margins = reader.document:getPageMargins()
                -- In vertical mode page height is the physical cross-axis
                -- allocation. A full-width line centers a narrow cover and
                -- leaves enough clip space on both sides of the image.
                local page_width = Screen:getWidth() - margins.left - margins.right
                assert.are.equal(page_width, reader.document._document:getPageHeight(1),
                    "isolated cover did not reserve the full page width")
            end
            local figure_page = reader.document:getPageFromXPointer(
                "/body[1]/DocFragment[3]/body[1]/img[1].0")
            assert.are.equal(figure_page, text_page,
                "an ordinary illustration forced an unwanted page break after it")

            if case.cover then
                -- A rebuilt formatter must derive the same cover region from
                -- its inputs, without relying on a correction in the drawer.
                reader.font:onSetFontSize(26)
                fastforward_ui_events()
                reader.rolling:onGotoPage(1)
                fastforward_ui_events()
                assert.are.equal(2, page_of(reader.document, "COVERTITLE"))
                local margins = reader.document:getPageMargins()
                assert.are.equal(Screen:getWidth() - margins.left - margins.right,
                    reader.document._document:getPageHeight(1),
                    "reformatting lost the cover region")

                reader:onClose()
                reader = nil
                reader = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(path),
                }
                UIManager:show(reader)
                fastforward_ui_events()
                assert.are.equal(2, page_of(reader.document, "COVERTITLE"))
                margins = reader.document:getPageMargins()
                assert.are.equal(Screen:getWidth() - margins.left - margins.right,
                    reader.document._document:getPageHeight(1),
                    "reopening lost the cover region")
            end
        end)
    end
end)
