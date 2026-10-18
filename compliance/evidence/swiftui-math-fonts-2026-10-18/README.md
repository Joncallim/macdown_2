# Retain the recorded 1.0 math-font set (#148)

MostlyText keeps all 12 SwiftUIMath fonts for 1.0. The inventory previously
reported that choice as undecided even though the release ledger already
recorded it. This correction removes only the obsolete decision entry and
records its source in the component notes. It changes no rendering, font
selection, bundled resource, licence, dependency or compliance-check rule.

Validated inventory candidate: **e14b677d85044dcfd4db141b87b24bc15a08dd34**.
Baseline: `aaec07288f96348fa6de651554991a865f1e4e96`. Later documentation/evidence
changes correct an extra blank line and record these results; they do not change
inventory or the product. See [validation.json](validation.json).

## Decision and preserved resources

A read-only issue retrieval on 2026-10-18 returned five comments. Both
[#148 comment 5867001043](https://github.com/Joncallim/macdown_2/issues/148#issuecomment-5867001043)
and [comment 5868785863](https://github.com/Joncallim/macdown_2/issues/148#issuecomment-5868785863)
record the owner's KEEP-all-12 decision. No later reversal appears in those
comments. They were posted under Joncallim through Claude; they are historical
decision evidence, not a new direct owner instruction or release approval.
`compliance/RELEASE_PREPARATION.md` already called for this reconciliation.

Only `swiftui-math-fonts.open_items` and `.notes` change in inventory. All 12
resource names/digests, four licence records, notices and other component fields
remain identical. Generated notices and the software bill of materials (SBOM)
regenerate byte-identically. The [decision record](decision-source.json) and
[independent review](INDEPENDENT_REVIEW.md) preserve the scope.

## What validation establishes

| Check | Outcome and limit |
| --- | --- |
| Baseline source archive | Ordinary compliance passes; release reports the original eight entries. Retained, not overwritten. |
| Committed candidate source archive | Ordinary compliance passes; release fails on exactly the same seven non-font findings. |
| Existing compliance regressions | Pass unchanged outside the sandbox. The first sandbox run failed on shell process substitution before the stubbed release flows could run. All original outputs are retained. |
| Generated output and product identity | Notices/SBOM are identical; complete MacDown2 tree remains `849a1e7562860034c02269a98929a6203fab44e8`, identical to the previously validated Release source. Pins match. |
| All 12 math fonts | Every required SHA-256 matches bytes in the retained unsigned Release app. This proves presence, not every distribution obligation. |
| Whole-app artifact compliance | **Fails on three findings**, detailed below. Same failures with baseline and candidate inventory. |
| Release check with artifact | **Fails on ten findings**: seven inventory findings plus the three artifact findings. |

The app was built on `7efb510c59ac75905a3c3b8fa1472d114ed81f2a`, as recorded in
the [preview checkpoint](../../../planning/downstream/evidence/preview-delivery-121-2026-10-18/README.md).
It was reused after proving unchanged complete product tree, generated output
and recorded executable hash. This is **not** a fresh build on e14b677d or a
signed-release artifact. All 165 regular artifact files are hashed in
[artifact-files.json](artifact-files.json); symlinks are outside that file hash
listing. No performance or native UI suite was rerun for bookkeeping-only changes.

## Artifact failures that remain

The retained app is missing the repository's `LICENSE` and the generated
`THIRD_PARTY_NOTICES.md`. It also ships the unregistered resource
`Contents/Resources/textual_Textual.bundle/Contents/Resources/prism-bundle.js`.
These failures are reproduced against both aaec0728 and e14b677d inventories;
they predate the font-decision correction.

The script's SHA-256,
`22b70192dc9d73377b5b8fe2c85655c7e3218afd37b65db638b4e168c4bacbf5`,
matches the clean, production-locked Textual checkout
`01b51875a5406eefc95f52a058cb059e7bc94dc4`. Its bundler declares Prism 1.29.0.
That source trace does not establish the complete bundled-code/licence
obligations. The bundler was inspected, never executed. Do not simply allowlist
this digest. Complete the attribution review before changing inventory/notices.

Bundling the first-party licence and generated notices is already specified by
[LICENCES_UI.md](../../LICENCES_UI.md). Its app integration remains incomplete.
All these artifact requirements and final signed-artifact verification remain
open. The font decision's removal cannot waive any of them.

## Failure retention and remaining boundaries

The initial test execution failed because the sandbox denied `/dev/fd/62` in
the release script's logging redirection. Identical tests passed outside the
sandbox using their existing temporary repositories and fake Apple tools. No
real signing, notarisation or submission occurred.

The first committed documentation had an extra blank line at the proposal's
end. Its `git diff --check` failure is retained; a documentation-only correction
removes that blank line. There was no threshold, assertion, checker or product
change to obtain a pass. Failed artifact checks remain failed.

The same checkpoint preserves the independently reviewed
[preview directory-grant proposal](../../../planning/downstream/issue-121-directory-grant-proposal.md).
It remains blocked on the file-only asset workflow and intended OS-access
configuration; no grant implementation was integrated. Delayed A still reads
root B in the retained reproduction. #53 writer protection, #203 performance,
hosted timing/styled-run failures, limited manual Pinyin coverage, native
security evidence and owner acceptance remain open.

Raw evidence:
`/Users/jonathanlim/GitHub/_cleanup-archive/preview-grants-fonts-aaec0728-2026-10-18/`.
See the [manifest](evidence-manifest.json) for retained commands, failures and
source archives. Master and dependency-trial work remain preserved. No push,
merge, issue closure, publication, signing, notarisation, release or deletion
of unique work occurred.
