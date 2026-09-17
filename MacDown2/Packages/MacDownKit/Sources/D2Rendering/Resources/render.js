// Harness glue between D2WebRenderer (Swift) and the bundled D2 library
// (d2-browser.js — see NOTICE.txt for the one-line modification from
// upstream), loaded alongside this file into an offscreen,
// network-isolated WKWebView (epic-21-implementation.md §3.7, mirroring
// epic-20-implementation.md §10's Mermaid containment exactly).
//
// Unlike Mermaid, no raster PNG snapshot is produced here: a real spike
// (epic-21-implementation.md Slice 0 as-built note) confirmed D2's
// native SVG output has no <foreignObject> and displays correctly via
// AppKit's own SVG decoder, so `svg` alone serves both Export and native
// on-screen Preview display.
window.__macdownRenderD2 = async function (source) {
    try {
        const d2 = new window.D2();
        const compiled = await d2.compile(source);
        const svg = await d2.render(compiled.diagram, compiled.renderOptions);
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
