// Harness glue between GraphvizWebRenderer (Swift) and the bundled
// viz-js library (viz-global.js, unmodified — see NOTICE.txt for the
// real license situation: MIT wrapper, EPL-2.0 Graphviz core), loaded
// alongside this file into an offscreen, network-isolated WKWebView
// (epic-21-implementation.md §3.7, mirroring epic-20-implementation.md
// §10's Mermaid containment exactly).
//
// Unlike Mermaid, no raster PNG snapshot is produced here: a real spike
// (epic-21-implementation.md Slice 0 as-built note) confirmed
// Graphviz's native SVG output has no <foreignObject> and displays
// correctly via AppKit's own SVG decoder, so `svg` alone serves both
// Export and native on-screen Preview display.
//
// The Viz WASM instance is created once per page (this harness is
// reused across many renders by the pool, epic-21-implementation.md
// §3.1) rather than once per render call.
var __vizInstancePromise = null;

function getViz() {
    if (!__vizInstancePromise) {
        __vizInstancePromise = window.Viz.instance();
    }
    return __vizInstancePromise;
}

window.__macdownRenderGraphviz = async function (source) {
    try {
        const viz = await getViz();
        const svg = viz.renderString(source, { format: "svg" });
        let width = 0;
        let height = 0;
        const viewBoxMatch = svg.match(/viewBox="([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)"/);
        if (viewBoxMatch) {
            width = parseFloat(viewBoxMatch[3]);
            height = parseFloat(viewBoxMatch[4]);
        }
        return { ok: true, svg: svg, width: width, height: height };
    } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    }
};
