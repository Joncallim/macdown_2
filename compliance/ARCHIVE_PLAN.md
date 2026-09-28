# Compliance archive plan (LC-09)

**Owner summary.** Two bundled components carry licences that require their
source code to be available whenever the app is distributed: Graphviz
(EPL-2.0, compiled into Viz.js) and D2 (MPL-2.0, which we modified by one
line). This plan says what we publish for each release, where, and how we
prove it can be downloaded. The recommended home is
`mostlytext.app/opensource/<version>/` for the index pages, with large source
packages attached to the matching GitHub Release. Nothing is published until
the E17 release process does it for a real release.

Risks: a URL printed in a shipped app must keep working for as long as that
release is distributed, so the layout below is versioned and never reused.
Owning the domain doesn't prove availability, so every location is downloaded
anonymously before public promotion. Non-goals: this doesn't choose the web
host (E17 does), and it never publishes credentials, signing or update keys,
or private material.

## Layout for each release

```text
mostlytext.app/opensource/
  index.html                       list of releases (website/opensource/index.html)
  <version>/
    THIRD_PARTY_NOTICES.md          byte-identical to the copy inside the app
    sbom.cdx.json                   byte-identical to the release SBOM
    SHA256SUMS                      digests of every file in this folder and every linked package
    graphviz/index.html             Graphviz + Viz.js corresponding source (LC-02)
    d2/index.html                   D2 corresponding source and our patch (LC-03)
```

Large packages are attached to the GitHub Release for the same tag. The
`graphviz/` and `d2/` pages link to them and list their SHA-256 digests.

## What each source page contains

| Component | Contents | Evidence to record in the inventory |
|---|---|---|
| Graphviz 16.0.0 via @viz-js/viz 3.30.0 | The upstream Graphviz 16.0.0 source archive; the viz-js 3.30.0 source at its release tag, including the Emscripten build scripts that produce the WebAssembly; the EPL-2.0 text; a note that we ship `dist/viz-global.js` from the npm package unmodified | Archive URLs and SHA-256; upstream tag commits; `npm_file_sha256` already recorded |
| D2 via @terrastruct/d2 0.1.33 | The upstream d2 source at the revision that produced npm 0.1.33 (the `d2js/js` package and the Go sources compiled into its WebAssembly); our patch as a unified diff (`export{lw as D2}` → `window.D2=lw;`); the MPL-2.0 text | Source revision and archive SHA-256; patch SHA-256; the Go module list, for LC-03's nested licences |

Other components are MIT, BSD, Apache-2.0, OFL or GUST licensed. Those
licences need notices, which LC-01 covers, but not a source offer. Their exact
upstream revisions are in the SBOM for anyone who wants the source.

## Retention and stable links

- Keep every release folder for as long as that release, or any update that
  could install it, is downloadable, and for at least three years after the
  last distribution. EPL-2.0 and MPL-2.0 don't set a period; three years is a
  conservative default.
- Never overwrite a published file. A correction goes in a new file, and
  `SHA256SUMS` records both.
- If hosting moves, redirect old URLs permanently (HTTP 301) to the new
  location and re-run the anonymous-download check.

## Verification before public promotion

1. Download every file listed in `SHA256SUMS` anonymously (no cookies, no
   GitHub login) from a network outside the build machine, and compare the
   digests.
2. Confirm that the app's `THIRD_PARTY_NOTICES.md` and `sbom.cdx.json` match
   the archive copies byte for byte.
3. Set `source_offer.status` to `"verified"` for Graphviz and D2 in
   `inventory.json`, recording the date and the command output, then run
   `compliance.py check --release --artifact <app>`.

All of this can run in a cloud session except extracting the files from the
signed app, which needs the DMG, a step that can be done on any machine once
the DMG exists.

## Order of work

1. **Now (cloud):** assemble the Graphviz and D2 source packages and patch,
   and record their digests in the inventory (LC-02, LC-03). This doesn't
   depend on hosting.
2. **At E17:** create the release folder from the release candidate's
   generated files, attach the packages to the draft GitHub Release, and
   deploy the pages.
3. **Before public promotion:** run the verification above and attach the
   evidence to #148 and #18.
