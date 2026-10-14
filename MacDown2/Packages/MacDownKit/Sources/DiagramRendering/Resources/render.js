// Harness glue between MermaidWebRenderer (Swift) and the bundled Mermaid
// library, loaded alongside this file into an offscreen, network-isolated
// WKWebView (epic-20-implementation.md §10). `securityLevel: 'strict'`
// disables Mermaid's own `click` interaction directives and sanitizes HTML
// inside diagram labels — defense in depth alongside the page's own CSP and
// the containing WKWebView's lack of network access.
mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    // Mermaid applies init directives and frontmatter config through the
    // same config sanitizer. Keep the product's neutral-light-v1 palette
    // authoritative by protecting the supported theme keys there, rather
    // than rewriting authored source text.
    secure: [
        "secure", "securityLevel", "startOnLoad", "maxTextSize",
        "suppressErrorRendering", "maxEdges", "theme", "themeVariables", "themeCSS"
    ]
});

// Real WebKit-composited raster snapshot resolution multiplier for the
// `png` field below (see the long comment on that field for why this
// exists at all). 2x keeps small diagrams crisp on a Retina display
// without the cost of Math's own 3x (`MathImageRenderer.standardScale`) —
// diagrams are typically larger/more detailed than a single equation, so
// output byte size matters more here.
var PREVIEW_RASTER_SCALE = 2;

var __macdownRenderCounter = 0;

// Rasterizes `svg` (Mermaid's own, unmodified output — including
// <foreignObject> HTML labels) via the standard canvas technique: load it
// as an <img> from a data: URI, draw that image onto a canvas, and read
// the canvas back out as a PNG data URL. This runs inside the SAME real
// WebKit engine that already renders <foreignObject>/CSS correctly for
// on-screen display — unlike AppKit's native SVG decoder (see the
// `png` field's doc comment) — so the result has full visual fidelity.
function rasterize(svg, width, height) {
    return new Promise((resolve, reject) => {
        var image = new Image();
        image.onload = () => {
            var canvas = document.createElement("canvas");
            canvas.width = Math.max(1, Math.round(width * PREVIEW_RASTER_SCALE));
            canvas.height = Math.max(1, Math.round(height * PREVIEW_RASTER_SCALE));
            var context = canvas.getContext("2d");
            context.drawImage(image, 0, 0, canvas.width, canvas.height);
            var dataURL = canvas.toDataURL("image/png");
            var prefix = "data:image/png;base64,";
            resolve(dataURL.startsWith(prefix) ? dataURL.slice(prefix.length) : dataURL);
        };
        image.onerror = () => reject(new Error("rasterization failed"));
        image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
    });
}

function positiveLength(value) {
    var text = String(value || "").trim();
    var match = text.match(/^([+]?\d+(?:\.\d*)?|[+]?\.\d+)(?:[eE][+-]?\d+)?(?:px)?$/i);
    if (!match) return 0;
    var number = Number(text.replace(/px$/i, ""));
    return Number.isFinite(number) && number > 0 ? number : 0;
}

function svgCanvasDimensions(root) {
    var viewBox = root.getAttribute("viewBox");
    var values = viewBox ? viewBox.trim().split(/[\s,]+/).map(Number) : [];
    var validViewBox = values.length === 4 && values.every(Number.isFinite) && values[2] > 0 && values[3] > 0;
    if (validViewBox) {
        return {
            x: values[0],
            y: values[1],
            width: values[2],
            height: values[3],
            usesViewBox: true,
            rectWidth: String(values[2]),
            rectHeight: String(values[3])
        };
    }

    var rectWidth = root.getAttribute("width") || "100%";
    var rectHeight = root.getAttribute("height") || "100%";
    return {
        x: 0,
        y: 0,
        width: positiveLength(rectWidth) || 1,
        height: positiveLength(rectHeight) || 1,
        usesViewBox: false,
        rectWidth: rectWidth,
        rectHeight: rectHeight
    };
}

function addOpaqueCanvas(svg) {
    var parser = new DOMParser();
    var document = parser.parseFromString(svg, "image/svg+xml");
    var root = document.documentElement;
    if (!root || root.nodeName.toLowerCase() !== "svg") return { svg: svg, width: 1, height: 1 };

    var dimensions = svgCanvasDimensions(root);
    if (!dimensions.usesViewBox) root.removeAttribute("viewBox");
    var rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", String(dimensions.x));
    rect.setAttribute("y", String(dimensions.y));
    rect.setAttribute("width", dimensions.rectWidth);
    rect.setAttribute("height", dimensions.rectHeight);
    rect.setAttribute("fill", "#FFFFFF");
    root.insertBefore(rect, root.firstChild);
    return {
        svg: new XMLSerializer().serializeToString(root),
        width: dimensions.width,
        height: dimensions.height
    };
}

// Returns a plain, JSON-serializable object so it bridges cleanly across
// WKWebView's evaluateJavaScript boundary:
// { ok: true, svg, png, width, height } on success, { ok: false, message }
// on failure. Never throws — every failure path is caught and reported
// through this same shape so the Swift side has one place to interpret a
// result.
//
// `svg` is Mermaid's own, unmodified vector output (genuinely resolution-
// independent) — this is what Export splices into HTML/PDF
// (epic-20-implementation.md §7.1) and it must keep Mermaid's richer
// default HTML-based labels, not a degraded native-<text> substitute.
//
// `png` is a real WebKit-rendered raster snapshot of that SAME svg, added
// after a real spike (see this repository's PR history for
// epic-20-implementation.md Slice 4) proved AppKit's own built-in SVG
// decoder (`NSImage`/`_NSSVGImageRep`) does not reliably display real
// Mermaid output: it silently drops every <foreignObject> label (a
// two-node "graph TD; A-->B;" rendered as two empty boxes joined by a
// line, no "A"/"B" text at all), and forcing Mermaid's `htmlLabels: false`
// escape hatch to work around that produced native <text> elements in the
// wrong vertical position (a further, apparently CSS-support-related
// AppKit SVG decoder limitation) — so native, on-screen Preview display
// uses this raster snapshot instead (mirroring `MathContribution`'s own
// PNG-based approach), while Export keeps using `svg` untouched, genuinely
// vector, and unaffected by any of this.
window.__macdownRenderMermaid = async function (source, theme) {
    __macdownRenderCounter += 1;
    var id = "macdown-diagram-" + __macdownRenderCounter;
    try {
        var foreground = theme && theme.foreground ? theme.foreground : "#000000";
        var background = theme && theme.background ? theme.background : "#FFFFFF";
        mermaid.initialize({
            startOnLoad: false,
            securityLevel: "strict",
            secure: [
                "secure", "securityLevel", "startOnLoad", "maxTextSize",
                "suppressErrorRendering", "maxEdges", "theme", "themeVariables", "themeCSS"
            ],
            theme: "base",
            themeVariables: {
                background: background,
                primaryColor: background,
                primaryTextColor: foreground,
                primaryBorderColor: foreground,
                lineColor: foreground,
                secondaryColor: background,
                tertiaryColor: background,
                pie1: "#4E79A7",
                pie2: "#F28E2B",
                pie3: "#59A14F",
                pie4: "#E15759",
                pie5: "#B07AA1",
                pie6: "#76B7B2",
                pie7: "#EDC949",
                pie8: "#FF9DA7",
                pie9: "#9C755F",
                pie10: "#BAB0AC",
                pie11: "#86BCB6",
                pie12: "#D37295",
                textColor: foreground
            }
        });
        var result = await mermaid.render(id, source);
        var canvas = addOpaqueCanvas(result.svg);
        var png = await rasterize(canvas.svg, canvas.width, canvas.height);
        return { ok: true, svg: canvas.svg, png: png, width: canvas.width, height: canvas.height };
    } catch (error) {
        var message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    } finally {
        // Mermaid's render() can leave a temporary measurement container in
        // the DOM on some failure paths. This offscreen page is reused
        // across many renders (pooled, epic-20-implementation.md §11), so
        // stray elements would otherwise accumulate for the life of the
        // pool entry.
        var stray = document.getElementById(id);
        if (stray && stray.parentNode) {
            stray.parentNode.removeChild(stray);
        }
    }
};

// The production renderer receives only Mermaid-generated SVG, but keeping
// this probe beside the production path lets package tests exercise the same
// real WebKit canvas/rasterization logic with SVG edge cases Mermaid does not
// normally emit (for example comma-separated viewBox values).
window.__macdownInspectMermaidSVG = async function (svg) {
    var canvas = addOpaqueCanvas(svg);
    var png = await rasterize(canvas.svg, canvas.width, canvas.height);
    return { svg: canvas.svg, png: png, width: canvas.width, height: canvas.height };
};
