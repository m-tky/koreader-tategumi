-- Regression for #94: an adjacent image must not suppress a writing-mode
-- boundary, and negative collapsed margins must not cross that boundary.
describe("Vertical text: mixed-mode page boundaries", function()
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
        UIManager._exit_code = nil
        if path then os.remove(path); path = nil end
    end)

    local function fixture(docs)
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
        add("figure.svg", [[<svg xmlns="http://www.w3.org/2000/svg" width="560" height="700" viewBox="0 0 560 700">
<rect width="560" height="700" fill="black"/></svg>]])
        -- Linked stylesheets let each DocFragment resolve its own writing mode.
        add("v.css", "html { writing-mode: vertical-rl }")
        add("h.css", "html { writing-mode: horizontal-tb }")
        local manifest, spine = {}, {}
        for i, doc in ipairs(docs) do
            add(doc.name, string.format([[<html xmlns="http://www.w3.org/1999/xhtml"><head>
<link rel="stylesheet" type="text/css" href="%s"/>
<style>
body { margin: 0; padding: 0 } p { margin: 0 }
img.keep-space { display: block; width: 0.1em; height: 0.1em; margin-right: -0.1em }
.p-title { margin-top: 25%%; padding-left: 5%%; padding-right: 5%%; text-align: center; line-height: 1.6 }
.p-title .book-title { margin: 0; padding-bottom: 2em; border-bottom: 1px solid #000000 }
.p-title .author { margin: 0; padding-top: 1em }
.p-caution { font-size: 0.9em; line-height: 1.6 }
</style></head><body>%s</body></html>]],
                doc.wm == "vertical-rl" and "v.css" or "h.css", doc.content))
            manifest[#manifest + 1] = string.format(
                '<item id="d%d" href="%s" media-type="application/xhtml+xml"/>', i, doc.name)
            spine[#spine + 1] = string.format('<itemref idref="d%d"/>', i)
        end
        manifest[#manifest + 1] = '<item id="fig" href="figure.svg" media-type="image/svg+xml"/>'
        manifest[#manifest + 1] = '<item id="v" href="v.css" media-type="text/css"/>'
        manifest[#manifest + 1] = '<item id="h" href="h.css" media-type="text/css"/>'
        add("book.opf", string.format([[<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">mixed-mode-page-boundary</dc:identifier>
<dc:title>Mixed mode page boundary regression</dc:title><dc:language>ja</dc:language>
<meta name="primary-writing-mode" content="vertical-rl"/></metadata>
<manifest>%s</manifest><spine page-progression-direction="rtl">%s</spine></package>]],
            table.concat(manifest), table.concat(spine)))
        writer:close()
        reader = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(reader)
        reader.document:setVisiblePageCount(1)
        fastforward_ui_events()
        return reader.document
    end

    local function paragraphs(prefix, count)
        local out = {}
        for i = 1, count do
            out[#out + 1] = string.format("<p>%s%02d　縦書きの本文です。</p>", prefix, i)
        end
        return table.concat(out)
    end

    local function page_of(doc, text)
        local hits = doc:findAllText(text, false, 0, 10, false)
        assert.truthy(hits and hits[1], "missing text: " .. text)
        return doc:getPageFromXPointer(hits[1].start)
    end

    it("keeps a vertical body off the preceding horizontal title page", function()
        local doc = fixture({
            {
                name = "title.xhtml", wm = "horizontal-tb",
                content = '<p class="dummy"><img class="keep-space" src="figure.svg"/></p>'
                    .. '<div class="p-title"><div class="book-title"><p>TITLEPAGE</p></div>'
                    .. '<div class="author"><p>SUBTITLE LINE</p></div>'
                    .. "<p><br/></p><p><br/></p><p><br/></p>"
                    .. '<div class="label"><p>PUBLISHER LABEL</p></div></div>',
            },
            {
                name = "body.xhtml", wm = "vertical-rl",
                content = '<p class="dummy"><img class="keep-space" src="figure.svg"/></p>'
                    .. '<div class="p-caution">' .. paragraphs("本文", 40) .. "</div>",
            },
        })
        local title_page = page_of(doc, "TITLEPAGE")
        local body_page = page_of(doc, "本文01")
        assert.is_true(body_page > title_page,
            "vertical body was laid out on the horizontal title page")
        assert.equals("horizontal-tb", doc:getPageWritingMode(title_page))
        assert.equals("vertical-rl", doc:getPageWritingMode(body_page))
    end)

    it("honors a writing-mode break next to an image without negative margins", function()
        local doc = fixture({
            { name = "title.xhtml", wm = "horizontal-tb", content = "<p>TITLEPAGE</p>" },
            {
                name = "body.xhtml", wm = "vertical-rl",
                content = '<p><img src="figure.svg" width="1" height="1"/></p><p>BODYTEXT</p>',
            },
        })
        local title_page = page_of(doc, "TITLEPAGE")
        assert.is_true(page_of(doc, "BODYTEXT") > title_page,
            "an image's avoid flag suppressed the writing-mode break")
        local image_xp = "/body[1]/DocFragment[2]/body[1]/p[1]/img[1].0"
        assert.is_true(doc:getPageFromXPointer(image_xp) > title_page)
        local page_end = doc._document:getPageStartY(title_page) + doc._document:getPageHeight(title_page)
        assert.is_true(doc:getPosFromXPointer(image_xp) >= page_end,
            "leading image crosses the writing-mode boundary")
    end)

    it("starts a leading explicit-height block on the new writing-mode page", function()
        local doc = fixture({
            { name = "title.xhtml", wm = "horizontal-tb", content = "<p>TITLEPAGE</p>" },
            {
                name = "body.xhtml", wm = "vertical-rl",
                content = '<div style="height: 40px"></div><p>BODYTEXT</p>',
            },
        })
        local title_page = page_of(doc, "TITLEPAGE")
        local block_y = doc:getPosFromXPointer("/body[1]/DocFragment[2]/body[1]/div[1].0")
        local page_end = doc._document:getPageStartY(title_page) + doc._document:getPageHeight(title_page)
        assert.is_true(block_y >= page_end, string.format(
            "leading block crosses the mode boundary: block_y=%d previous_end=%d", block_y, page_end))
        assert.is_true(page_of(doc, "BODYTEXT") > title_page)
    end)

    it("discards a negative margin at a horizontal forced break", function()
        local doc = fixture({
            {
                name = "text.xhtml", wm = "horizontal-tb",
                content = '<p>BEFOREBREAK</p>'
                    .. '<p style="page-break-before: always; margin-top: -8px">AFTERBREAK</p>',
            },
        })
        assert.is_true(page_of(doc, "AFTERBREAK") > page_of(doc, "BEFOREBREAK"),
            "negative margin suppressed a horizontal forced break")
    end)

    it("does not add discarded negative margins to an explicit block height", function()
        local doc = fixture({
            {
                name = "text.xhtml", wm = "horizontal-tb",
                content = '<p>BEFOREBREAK</p>'
                    .. '<div style="page-break-before: always; height: 40px; margin-top: -8px"></div>'
                    .. '<p>AFTERBLOCK</p>',
            },
        })
        local block_y = doc:getPosFromXPointer("/body[1]/DocFragment[1]/body[1]/div[1].0")
        local after_y = doc:getPosFromXPointer("/body[1]/DocFragment[1]/body[1]/p[2].0")
        assert.equals(40, after_y - block_y, "discarded margin inflated explicit block height")
    end)

    it("keeps a horizontal illustration entirely after the preceding vertical page", function()
        local doc = fixture({
            { name = "text.xhtml", wm = "vertical-rl", content = paragraphs("直前", 6) },
            {
                name = "figure.xhtml", wm = "horizontal-tb",
                content = '<p class="dummy"><img class="keep-space" src="figure.svg"/></p>'
                    .. '<p><img src="figure.svg" width="560" height="700"/></p>',
            },
            { name = "after.xhtml", wm = "vertical-rl", content = "<p>AFTERFIGURE</p>" },
        })
        local text_page = page_of(doc, "直前06")
        local image_xp = "/body[1]/DocFragment[2]/body[1]/p[2]/img[1].0"
        local figure_page = doc:getPageFromXPointer(image_xp)
        assert.is_true(figure_page > text_page, "illustration was not given its own page")
        local image_y = doc:getPosFromXPointer(image_xp)
        local page_end = doc._document:getPageStartY(text_page) + doc._document:getPageHeight(text_page)
        assert.is_true(image_y >= page_end, string.format(
            "illustration crosses the previous page boundary: image_y=%d previous_end=%d", image_y, page_end))
        assert.equals("horizontal-tb", doc:getPageWritingMode(figure_page))
        reader.rolling:onGotoPage(text_page)
        fastforward_ui_events()
        assert.equals(0, doc._drawn_images_count,
            "illustration was also drawn on the preceding text page")
        reader.rolling:onGotoPage(figure_page)
        fastforward_ui_events()
        assert.is_true(doc._drawn_images_count > 0, "illustration was not drawn on its own page")
        assert.is_true(doc._drawn_images_surface_ratio > 0.1,
            "only the tiny spacer was drawn, not the large illustration")
        assert.equals("vertical-rl", doc:getPageWritingMode(page_of(doc, "AFTERFIGURE")))
    end)
end)
