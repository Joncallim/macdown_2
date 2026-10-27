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
function opaqueD2Canvas(svg, fill) {
    const document = new DOMParser().parseFromString(svg, "image/svg+xml");
    const root = document.documentElement;
    if (!root || root.localName !== "svg") throw new Error("invalid D2 SVG root");
    const values = (root.getAttribute("viewBox") || "").trim().split(/[\s,]+/).map(Number);
    if (values.length !== 4 || !values.every(Number.isFinite) || values[2] <= 0 || values[3] <= 0) {
        throw new Error("invalid D2 SVG dimensions");
    }
    // D2's generated background is the first rect in its nested SVG. AppKit's
    // SVG decoder does not apply D2's scoped CSS class to that rect and paints
    // it black. Make the generated light-profile background literal while
    // leaving every authored shape/style untouched. Only match the bundled
    // neutral profile's actual class and CSS declaration.
    const diagramRoot = root.firstElementChild;
    const background = diagramRoot && diagramRoot.localName === "svg" ? diagramRoot.firstElementChild : null;
    const styles = diagramRoot ? Array.from(diagramRoot.childNodes)
        .filter(node => node.localName === "style").map(node => node.textContent).join("\n") : "";
    if (background && background.localName === "rect" &&
        background.getAttribute("class")?.trim() === "fill-N7" &&
        /\.fill-N7\s*\{\s*fill:\s*#FFFFFF\s*;/i.test(styles)) {
        background.removeAttribute("class");
        background.setAttribute("fill", "#FFFFFF");
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

window.__macdownRenderD2 = async function (source, theme) {
    try {
        if (!theme || theme.policyID !== "neutral-light-v1") {
            throw new Error("unsupported diagram palette");
        }
        const d2 = new window.D2();
        const compiled = await d2.compile(source);
        // This bundled D2.js version documents themeID/darkThemeID. Pin
        // defaults across WebKit appearances, while retaining a theme
        // explicitly authored in the D2 source.
        const authored = compiled.renderOptions || {};
        const options = Object.assign({ themeID: 0, darkThemeID: 0 }, authored);
        if (authored.themeID != null && authored.darkThemeID == null) {
            options.darkThemeID = authored.themeID;
        }
        const svg = await d2.render(compiled.diagram, options);
        const canvas = opaqueD2Canvas(svg, theme.canvas);
        return { ok: true, svg: canvas.svg, width: canvas.width, height: canvas.height };
    } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    }
};
