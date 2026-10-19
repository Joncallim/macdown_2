# Contained document-directory acquisition for preview (#121)

## Owner summary

When a person explicitly allows a folder for preview resources, a document inside
that folder needs its own resource base. This narrow change lets the resource
reader pin that document directory through the already opened folder, without
reopening an approved pathname. If the directory or an ancestor changes during
acquisition, it rejects the new object. It does not show the **Allow preview
resources** chooser or give a file-only document access to nearby files.

The integration baseline for this spike is `c4b9013b254af3421701b39ce182aa8e3a022393`,
separate from the clean commit under hosted validation in draft PR #493. Live
`master` at inspection was `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`.
The [#121 handoff](issue-121-handoff.md),
[directory-grant proposal](issue-121-directory-grant-proposal.md),
`planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md` remain the
release contract. The owner chose a visible folder chooser for a file opened by
itself; this primitive cannot infer that grant from a URL.

## Scope and mechanism

`LocalResourceAccess.DirectoryLease.childDirectory(_:)` takes a parsed relative
directory reference from a pinned parent lease. It rejects empty or forged
components, even when callers bypass `ResourceReference.parse`. It resolves a
canonical **hint** for legitimate in-root symlinks and captures the intended
child's strict filesystem identity. The real acquisition uses `openat` from the
held parent descriptor with `O_DIRECTORY | O_NOFOLLOW_ANY |
O_RESOLVE_BENEATH`, then compares `fstat` identity with the observed child.
Root and child name checks reject a replacement before publication. The
returned child owns a distinct descriptor; closing the parent after admission
does not retarget or close the child. An empty document-relative path can use
the original root lease without calling this method.

The canonical hint and identity observation cannot by themselves establish
permission. The application must capture a typed folder-selection grant before
this operation, retain its security scope through actual reads, and check the
same document/grant epoch after acquisition. This synchronous primitive also
does not supply an I/O worker budget, cancellation or retained-byte accounting.
No app, preview, Export, project, package dependency or lockfile changes are
included in this slice.

## Focused evidence and limits

On macOS 26.5.1 (25F80), Xcode 26.6 (17F113), macOS SDK 26.5, the serial,
forced-pin command below passed all nine focused Swift Testing controls from
the c4 baseline plus this source diff:

```sh
cd MacDown2/Packages/MacDownKit
swift test --force-resolved-versions --no-parallel --filter ChildDirectoryLeaseTests
```

The controls cover ordinary document-relative reads, allowed and denied
symlinks, forged references, an ordinary replacement before the real open,
root replacement, a same-object ancestor symlink swap that the final identity
check alone would accept, a post-open replacement with descriptor-count return
to baseline, replacement after acquisition and parent closure during handoff.
The same-object swap is the check that discriminates the kernel's no-follow
enforcement from the separate identity and name guards. Expected results are
the original sentinel bytes or denial/changed-root; no replacement or outside
sentinel is admitted. Strict SwiftLint, SwiftFormat and diff-whitespace checks
passed for the changed files.

The first expanded run stopped before compilation because SwiftPM's manifest
subprocess received `sandbox_apply: Operation not permitted`. The same source
and command then passed with the executor sandbox restriction lifted. Both
outcomes and source hashes are retained under
`/Users/jonathanlim/GitHub/_cleanup-archive/hosted-c4b9013b-2026-10-19/`
as `child-lease-focused-expanded.json`,
`child-lease-focused-expanded-unsandboxed.json` and their corresponding logs.
The earlier seven-control first run is retained there separately. These are
local filesystem controls on one supported OS/SDK, not native app evidence on
the minimum macOS 26.0 release target or proof of the complete #121 contract.

The current native Markdown preview still relies on Textual's default image
loader, and HTML preview still has a mutable resource root and a path-approved
absolute reopen. Exposing the chooser before both paths share bounded,
immutable contained reads would leave a bypass. Export has its own source
authorization decision; a preview-only folder choice must not silently grant
it. No #121 closure or release promotion follows from this spike.
