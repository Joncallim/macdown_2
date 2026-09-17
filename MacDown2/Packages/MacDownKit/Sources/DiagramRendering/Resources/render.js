// Harness glue between MermaidWebRenderer (Swift) and the bundled Mermaid
// library, loaded alongside this file into an offscreen, network-isolated
// WKWebView (epic-20-implementation.md §10). `securityLevel: 'strict'`
// disables Mermaid's own `click` interaction directives and sanitizes HTML
// inside diagram labels — defense in depth alongside the page's own CSP and
// the containing WKWebView's lack of network access.
mermaid.initialize({ startOnLoad: false, securityLevel: "strict" });

var __macdownRenderCounter = 0;

// Returns a plain, JSON-serializable object so it bridges cleanly across
// WKWebView's evaluateJavaScript boundary: { ok: true, svg, width, height }
// on success, { ok: false, message } on failure. Never throws — every
// failure path is caught and reported through this same shape so the Swift
// side has one place to interpret a result.
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
        return { ok: true, svg: svg, width: width, height: height };
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
