// Harness glue between MermaidWebRenderer (Swift) and the bundled Mermaid
// library, loaded alongside this file into an offscreen, network-isolated
// WKWebView (epic-20-implementation.md §10). `securityLevel: 'strict'`
// disables Mermaid's own `click` interaction directives and sanitizes HTML
// inside diagram labels — defense in depth alongside the page's own CSP and
// the containing WKWebView's lack of network access.
mermaid.initialize({ startOnLoad: false, securityLevel: "strict" });

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
window.__macdownRenderMermaid = async function (source) {
    __macdownRenderCounter += 1;
    var id = "macdown-diagram-" + __macdownRenderCounter;
    try {
        var result = await mermaid.render(id, source);
        var svg = result.svg;
        var width = 0;
        var height = 0;
        var viewBoxMatch = svg.match(/viewBox="([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)"/);
        if (viewBoxMatch) {
            width = parseFloat(viewBoxMatch[3]);
            height = parseFloat(viewBoxMatch[4]);
        }
        var png = await rasterize(svg, width || 1, height || 1);
        return { ok: true, svg: svg, png: png, width: width, height: height };
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
