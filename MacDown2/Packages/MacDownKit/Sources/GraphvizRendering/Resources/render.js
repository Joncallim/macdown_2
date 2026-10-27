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

function opaqueGraphvizCanvas(svg, fill) {
    const document = new DOMParser().parseFromString(svg, "image/svg+xml");
    const root = document.documentElement;
    if (!root || root.localName !== "svg") throw new Error("invalid Graphviz SVG root");
    const values = (root.getAttribute("viewBox") || "").trim().split(/[\s,]+/).map(Number);
    if (values.length !== 4 || !values.every(Number.isFinite) || values[2] <= 0 || values[3] <= 0) {
        throw new Error("invalid Graphviz SVG dimensions");
    }
    const canvas = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    canvas.setAttribute("x", String(values[0]));
    canvas.setAttribute("y", String(values[1]));
    canvas.setAttribute("width", String(values[2]));
    canvas.setAttribute("height", String(values[3]));
    canvas.setAttribute("fill", fill);
    root.insertBefore(canvas, root.firstChild);
    return { svg: new XMLSerializer().serializeToString(root), width: values[2], height: values[3] };
}

window.__macdownRenderGraphviz = async function (source, theme) {
    try {
        if (!theme || !["neutral-light-v1", "preview-context-v1"].includes(theme.policyID)) {
            throw new Error("unsupported diagram palette");
        }
        const viz = await getViz();
        const background = theme && theme.canvas ? theme.canvas : "#FFFFFF";
        const options = {
            format: "svg",
            graphAttributes: { bgcolor: background, fontcolor: theme.text },
            nodeAttributes: { fontcolor: theme.text }
        };
        // Native DOT defaults have lower precedence than authored
        // graph/node/edge attributes, including explicit black paint.
        Object.assign(options.graphAttributes, { color: theme.stroke, fillcolor: theme.canvas });
        Object.assign(options.nodeAttributes, { color: theme.stroke, fillcolor: theme.nodeFill });
        options.edgeAttributes = { color: theme.stroke, fontcolor: theme.text };
        const svg = viz.renderString(source, options);
        const canvas = opaqueGraphvizCanvas(svg, background);
        return { ok: true, svg: canvas.svg, width: canvas.width, height: canvas.height };
    } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    }
};
