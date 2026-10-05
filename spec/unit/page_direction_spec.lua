describe("Page direction metadata detector", function()
    local PageDirection

    setup(function()
        require("commonrequire")
        PageDirection = require("util/page_direction")
    end)

    describe("EPUB OPF", function()
        local function detect(container, opf)
            local path = os.tmpname()
            os.remove(path)
            path = path .. ".epub"
            finally(function() os.remove(path) end)
            local writer = require("ffi/archiver").Writer:new()
            assert.is_true(writer:open(path, "zip"))
            assert.is_true(writer:addFileFromMemory("META-INF/container.xml", container))
            assert.is_true(writer:addFileFromMemory("book.opf", opf))
            writer:close()
            return PageDirection.getDirection({file = path})
        end

        it("accepts both quote styles, namespaces and attribute whitespace", function()
            for _, quote in ipairs({'"', "'"}) do
                local container = '<c:container xmlns:c="urn:oasis:names:tc:opendocument:xmlns:container">' ..
                    "<c:rootfile full-path = " .. quote .. "book.opf" .. quote .. "/></c:container>"
                local opf = '<opf:package xmlns:opf="http://www.idpf.org/2007/opf">' ..
                    "<opf:spine page-progression-direction = " .. quote .. "RTL" .. quote .. "/></opf:package>"
                assert.equals("rtl", detect(container, opf))
            end
        end)

        it("handles entities and quoted tag delimiters", function()
            assert.equals("rtl", detect(
                '<container><rootfile note="a > b" full-path="book&#46;opf"/></container>',
                '<package><spine note="a > b" page-progression-direction="rtl"/></package>'))
        end)

        it("ignores comments, CDATA, similarly named elements and unsupported directions", function()
            local container = '<container><rootfile full-path="book.opf"/></container>'
            assert.equals("ltr", detect(container, [=[
                <package><!-- <spine page-progression-direction="rtl"/> -->
                <![CDATA[<spine page-progression-direction="rtl"/>]]>
                <spineExtra page-progression-direction="rtl"/>
                <spine page-progression-direction="ltr"/></package>
            ]=]))
            assert.is_nil(detect(container, '<package><spine page-progression-direction="default"/></package>'))
        end)
    end)

    describe("ComicInfo.xml", function()
        it("finds and parses ComicInfo.xml inside a CBZ archive", function()
            local Archiver = require("ffi/archiver")
            local cbz_path = os.tmpname() .. ".cbz"
            finally(function() os.remove(cbz_path) end)

            local writer = Archiver.Writer:new()
            assert.is_true(writer:open(cbz_path, "zip"))
            assert.is_true(writer:addFileFromMemory("metadata/ComicInfo.xml", [[
                <ComicInfo><Manga>YesAndRightToLeft</Manga></ComicInfo>
            ]]))
            assert.is_true(writer:addFileFromMemory("001.jpg", "not-an-image"))
            writer:close()

            assert.equals("rtl", PageDirection.getDirection({ file = cbz_path }))
        end)

        it("detects the standard right-to-left Manga enum", function()
            assert.equals("rtl", PageDirection.parseComicInfo([[
                <?xml version="1.0"?>
                <ComicInfo xmlns="http://example.invalid/comicinfo">
                    <Manga>YesAndRightToLeft</Manga>
                </ComicInfo>
            ]]))
        end)

        it("accepts namespaced elements, attributes, comments and a BOM", function()
            assert.equals("rtl", PageDirection.parseComicInfo("\239\187\191" .. [[
                <ci:ComicInfo xmlns:ci="urn:comicinfo">
                    <!-- <ci:Manga>No</ci:Manga> -->
                    <ci:Manga source="tagger"> YesAndRightToLeft </ci:Manga>
                </ci:ComicInfo>
            ]]))
        end)

        it("does not infer direction from the other standard Manga values", function()
            for _, value in ipairs({ "Unknown", "No", "Yes" }) do
                assert.is_nil(PageDirection.parseComicInfo(
                    "<ComicInfo><Manga>" .. value .. "</Manga></ComicInfo>"))
            end
        end)

        it("accepts legacy and descriptive ReadingDirection values", function()
            for _, value in ipairs({ "RTL", "rtl", "RightToLeft", "right-to-left", "right_to_left" }) do
                assert.equals("rtl", PageDirection.parseComicInfo(
                    "<ComicInfo><ReadingDirection>" .. value
                    .. "</ReadingDirection></ComicInfo>"))
            end
            for _, value in ipairs({ "LTR", "LeftToRight", "left-to-right" }) do
                assert.equals("ltr", PageDirection.parseComicInfo(
                    "<ComicInfo><ReadingDirection>" .. value
                    .. "</ReadingDirection></ComicInfo>"))
            end
        end)

        it("prefers the standard RTL Manga value over a conflicting extension", function()
            assert.equals("rtl", PageDirection.parseComicInfo([[
                <ComicInfo>
                    <Manga>YesAndRightToLeft</Manga>
                    <ReadingDirection>LTR</ReadingDirection>
                </ComicInfo>
            ]]))
        end)

        it("returns unknown for missing, malformed and unsupported values", function()
            assert.is_nil(PageDirection.parseComicInfo(nil))
            assert.is_nil(PageDirection.parseComicInfo("<ComicInfo/>"))
            assert.is_nil(PageDirection.parseComicInfo(
                "<ComicInfo><MangaFoo>YesAndRightToLeft</MangaFoo></ComicInfo>"))
            assert.is_nil(PageDirection.parseComicInfo(
                "<ComicInfo><ReadingDirection>sideways</ReadingDirection></ComicInfo>"))
        end)
    end)
end)
