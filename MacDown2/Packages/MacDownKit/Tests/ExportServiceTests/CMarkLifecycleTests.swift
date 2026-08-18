@testable import ExportService
import Testing

/// Slice 0: cmark dependency/lifetime/custom-node proof. These tests exercise
/// the isolated cmark-gfm bridge directly — GFM extensions, raw-HTML policy,
/// the tagfilter guard, and custom inline/block nodes — without going through
/// the full composer.
struct CMarkLifecycleTests {
    @Test func rendersOrdinaryMarkdown() throws {
        let html = try CMarkGFM.renderHTML("# Hello\n\nworld", options: CMarkGFM.optUnsafe)
        #expect(html.contains("<h1>Hello</h1>"))
        #expect(html.contains("<p>world</p>"))
    }

    @Test func rendersGFMTable() throws {
        let markdown = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        let html = try CMarkGFM.renderHTML(markdown, options: CMarkGFM.optUnsafe)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>a</th>"))
        #expect(html.contains("<td>2</td>"))
    }

    @Test func rendersGFMStrikethrough() throws {
        let html = try CMarkGFM.renderHTML("~~gone~~", options: CMarkGFM.optUnsafe)
        #expect(html.contains("<del>gone</del>"))
    }

    @Test func rendersGFMTaskList() throws {
        let html = try CMarkGFM.renderHTML("- [x] done\n- [ ] todo\n", options: CMarkGFM.optUnsafe)
        #expect(html.contains("checkbox"))
        #expect(html.contains("checked"))
        #expect(html.contains("done"))
        #expect(html.contains("todo"))
    }

    @Test func preservesRawHTMLUnderUnsafe() throws {
        let html = try CMarkGFM.renderHTML("<b>bold</b>", options: CMarkGFM.optUnsafe)
        #expect(html.contains("<b>bold</b>"))
    }

    @Test func omitsRawHTMLWithoutUnsafe() throws {
        let html = try CMarkGFM.renderHTML("<b>bold</b>", options: CMarkGFM.optDefault)
        #expect(!html.contains("<b>bold</b>"))
        #expect(html.contains("raw HTML omitted"))
    }

    @Test func tagfilterNeutralisesScriptTags() throws {
        let html = try CMarkGFM.renderHTML("<script>alert(1)</script>", options: CMarkGFM.optUnsafe)
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script"))
    }

    @Test func blockCustomNodeRendersDerivedHTML() throws {
        let sentinel = "E12BLOCK0"
        let html = try CMarkGFM.renderHTML(
            "\n\n\(sentinel)\n\n",
            options: CMarkGFM.optUnsafe,
            customNodes: [CMarkGFM.CustomNodeSpec(sentinel: sentinel, isBlock: true, html: "<figure>diagram</figure>")]
        )
        #expect(html.contains("<figure>diagram</figure>"))
        #expect(!html.contains(sentinel))
    }

    @Test func inlineCustomNodeRendersDerivedHTML() throws {
        let sentinel = "E12INLINE0"
        let html = try CMarkGFM.renderHTML(
            "see \(sentinel) here",
            options: CMarkGFM.optUnsafe,
            customNodes: [
                CMarkGFM.CustomNodeSpec(
                    sentinel: sentinel,
                    isBlock: false,
                    html: "<span class=\"math\">x</span>"
                ),
            ]
        )
        #expect(html.contains("<span class=\"math\">x</span>"))
        #expect(!html.contains(sentinel))
        #expect(html.contains("see"))
        #expect(html.contains("here"))
    }

    @Test func inlineCustomNodeSplitsEmbeddedText() throws {
        // The sentinel is glued to surrounding text with no whitespace — the
        // bridge must split the text node rather than drop or misrender it.
        let sentinel = "E12INLINE0"
        let html = try CMarkGFM.renderHTML(
            "pre\(sentinel)post",
            options: CMarkGFM.optUnsafe,
            customNodes: [CMarkGFM.CustomNodeSpec(sentinel: sentinel, isBlock: false, html: "<em>mid</em>")]
        )
        #expect(html.contains("pre"))
        #expect(html.contains("<em>mid</em>"))
        #expect(html.contains("post"))
        #expect(!html.contains(sentinel))
    }

    @Test func rewritesImageURLsViaTransformer() throws {
        let html = try CMarkGFM.renderHTML(
            "![alt](images/foo.png)",
            options: CMarkGFM.optUnsafe,
            urlTransformer: { url, isImage in
                if isImage, url == "images/foo.png" {
                    return .rewrite("report.assets/abc.png")
                }
                return .keep
            }
        )
        #expect(html.contains("src=\"report.assets/abc.png\""))
    }

    @Test func blanksDangerousLinkURLsViaTransformer() throws {
        let html = try CMarkGFM.renderHTML(
            "[x](javascript:alert(1))",
            options: CMarkGFM.optUnsafe,
            urlTransformer: { url, _ in
                ExportURLPolicy.isSafe(url) ? .keep : .blank
            }
        )
        #expect(!html.contains("javascript:"))
    }

    @Test func repeatedRendersDoNotLeakOrCorrupt() throws {
        // A lifecycle smoke test: many sequential renders must stay stable,
        // which a leaked tree/buffer would not.
        for _ in 0 ..< 200 {
            let html = try CMarkGFM.renderHTML("# h\n\n`code`", options: CMarkGFM.optUnsafe)
            #expect(html.contains("<h1>h</h1>"))
        }
    }

    @Test func reportsAuthoredRawHTML() throws {
        let block = try CMarkGFM.render("<div>x</div>", options: CMarkGFM.optUnsafe)
        #expect(block.containsRawHTML)

        let inline = try CMarkGFM.render("text <b>x</b> more", options: CMarkGFM.optUnsafe)
        #expect(inline.containsRawHTML)

        // Detection reads the tree, so it holds even when the render option
        // strips the markup back out again.
        let stripped = try CMarkGFM.render("<div>x</div>", options: CMarkGFM.optDefault)
        #expect(stripped.containsRawHTML)

        let plain = try CMarkGFM.render("# just markdown\n\n- a\n", options: CMarkGFM.optUnsafe)
        #expect(!plain.containsRawHTML)
    }

    @Test func longerSentinelsWinOverTheirOwnPrefixes() throws {
        // `E12INLINE1Z` must not be matched inside `E12INLINE10Z`.
        let specs = [
            CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE1Z", isBlock: false, html: "<i>one</i>"),
            CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE10Z", isBlock: false, html: "<i>ten</i>"),
        ]
        let html = try CMarkGFM.renderHTML(
            "a E12INLINE1Z b E12INLINE10Z c",
            options: CMarkGFM.optUnsafe,
            customNodes: specs
        )
        #expect(html.contains("<i>one</i>"))
        #expect(html.contains("<i>ten</i>"))
        #expect(!html.contains("E12INLINE"))
    }

    @Test func textThatOnlyLooksLikeASentinelIsUntouched() throws {
        let html = try CMarkGFM.renderHTML(
            "prefix E12INLINE but not a sentinel, and E12INLINE0Z is",
            options: CMarkGFM.optUnsafe,
            customNodes: [CMarkGFM.CustomNodeSpec(sentinel: "E12INLINE0Z", isBlock: false, html: "<i>hit</i>")]
        )
        #expect(html.contains("<i>hit</i>"))
        #expect(html.contains("E12INLINE but not a sentinel"))
    }
}
