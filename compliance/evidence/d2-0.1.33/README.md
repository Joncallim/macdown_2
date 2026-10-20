# D2 browser source and Go-module audit (#148 LC-03)

## Owner summary

The shipped D2 browser bundle is now tied byte-for-byte to the official npm
package and its one local export replacement. The publisher's npm metadata
names an immutable upstream source commit. Querying that commit's documented
Go-to-WebAssembly target reaches 16 external Go modules, each with an exact
version, Go checksum and captured root licence-text hash in
[`source-graph.json`](source-graph.json). This is useful source-availability and
attribution preparation, not a completed release gate: the package publisher's
binary was not independently rebuilt, nested/embedded texts have not been
fully reviewed, the complete source offer has not been assembled or published,
and the final app has not been checked. No inventory `open_items` or
`source_offer.status` is changed.

## Inputs and findings

Official [npm metadata](https://registry.npmjs.org/@terrastruct%2fd2/0.1.33)
reports `@terrastruct/d2@0.1.33`, repository directory `d2js/js`, and
`gitHead` [`581c91096b62d644fb5168313142c836b7e68e74`](https://github.com/d2lang/d2/commit/581c91096b62d644fb5168313142c836b7e68e74).
The [npm archive](https://registry.npmjs.org/@terrastruct/d2/-/d2-0.1.33.tgz)
matches the registry's SHA-512 integrity value. Its SHA-256 is
`b84f8fe9b8d4e32223a436a54aa47867179856612174e803c04a725c93834191`.
The upstream `dist/browser/index.js` SHA-256 is
`9898965444a940cdbedda3b039f717e96a86ffe9b3170bf30f8fea94ffb66e8a`.
The shipped file SHA-256 is
`991a44779c91b74cbdf141228a6ba34592fe9b708fe19c221eba9ef4a7cfe33e`.
The exact change is one replacement after a shared 8,194,848-byte prefix:
`export{lw as D2}` becomes `window.D2=lw;`; the final two bytes are shared.

The [source archive at that commit](https://github.com/d2lang/d2/archive/581c91096b62d644fb5168313142c836b7e68e74.tar.gz)
has SHA-256 `91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391`.
Its `d2js/js/ci/build.sh` invokes `GOOS=js GOARCH=wasm go build` on
`./d2js` with Go 1.24.6. The source checkout's `package.json` says 0.1.32;
the same release script sets the npm publication version to 0.1.33. The
published npm archive contains two identical `d2.wasm` copies (SHA-256
`7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af`).
The shipped browser bundle is the verified npm output, but this audit has not
reproduced its JavaScript or WebAssembly build.

With a checksum-verified, temporary official Go 1.24.6 toolchain and the
source archive extracted locally, `GOOS=js GOARCH=wasm go list -deps -json
./d2js` completed with no package errors: 288 packages and 16 external modules.
The manifest records each selected module's version, Go sum, source-package
count and root licence-text filename/hash. The FreeType module's licence is a
dual-choice text; its distribution choice and any nested code/NOTICE duties
require review before these texts are installed into shipped notices. The
source graph is not proof that the npm publisher built exactly these bytes
from this commit; npm `gitHead` is publisher provenance, not a rebuild attestation.

## Reproduction and controls

Raw npm metadata, integrity-checked npm archive, source archive, the extracted
WebAssembly, Go download manifest/toolchain, Go package graph and stderr are
retained under
`/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/`.
The temporary Go archive's SHA-256
`4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a`
matches the official [Go download manifest](https://go.dev/dl/?mode=json&include=all).
No system Go installation or website change was made.

From the repository root, with those inputs available:

```sh
python3 compliance/tools/audit_d2_source.py \
  --metadata /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/npm-metadata.json \
  --npm /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2-0.1.33.tgz \
  --source /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2-source-581c9109.tar.gz \
  --go-list /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2js-wasm-go-list.json \
  --shipped MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js \
  --output /tmp/d2-source-graph.json
cmp compliance/evidence/d2-0.1.33/source-graph.json /tmp/d2-source-graph.json
```

The Go graph was generated in the extracted source root with:

```sh
env GOOS=js GOARCH=wasm GOTOOLCHAIN=local \
  GOMODCACHE=/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/gomodcache \
  GOCACHE=/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/gocache \
  /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/go/bin/go list -deps -json ./d2js
```

The audit rejects an npm tarball that violates registry integrity, a shipped
bundle changed beyond the exact export replacement, and a Go graph with an
incomplete package. Its negative-control results are retained with the raw
inputs (`negative-controls.log`): all three controls failed as intended.
`python3 -m py_compile compliance/tools/audit_d2_source.py`,
`python3 compliance/tools/compliance.py check`, and `git diff --check` passed.
The existing compliance suite passed 82 tests under the authorized executor.
Its first default-sandbox launch failed 10 release-script fixtures before their
assertions because Bash could not open `/dev/fd/62`; both logs are retained.
The ordinary tree compliance check remains green; the strict release check
still has the same seven pre-existing findings.

## Remaining LC-03 work

Review module and nested-code licence obligations, include the required
texts in the inventory and generated notices, assemble a complete immutable
source package plus local patch, and obtain independent provenance review.
Source-only public publication and anonymous retrieval belong to the later
owner-authorized LC-09 phase. Keep #148 open until preflight and final
exact-artifact criteria are met.
