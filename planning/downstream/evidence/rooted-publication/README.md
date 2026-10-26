# Rooted Replace in Folder publication probe (#183 F14)

## Owner summary

Replace in Folder must never rewrite a file outside the folder the user chose.
The current implementation checks for symbolic links during the reviewed
snapshot, then awaits a second open-document protection result before writing
through a file path. Another process can move a directory and replace that
path during the wait. The file
can retain the exact revision the user reviewed while the write is redirected
outside the chosen folder.

Holding an open descriptor for the original directory prevents a replacement
symbolic link from redirecting the final operation. It does **not**, by itself,
prove that directory still belongs to the chosen folder. This probe verifies
that limit. No production behavior changed, and #183 F14 is not closed.

## Current boundary and result

`WorkspaceReplaceEngine.verifiedSnapshot` rejects already visible symbolic
links, but `apply` later calls path-based `FileStore.write` after another await
and the `beforeWrite` test boundary. `FileStore` eventually exchanges the staged
file using `renameatx_np(AT_FDCWD, ...)`. The existing regression suite covers
pre-existing links and competing file bytes; it does not cover a parent moved
after the reviewed snapshot.

The adjacent constrained reader in LocalResourceAccess holds a root descriptor
and opens descendants without following symbolic links. FileCore cannot import
that module without a new dependency, and copying only its descriptor pattern
does not solve publication membership.

On macOS 26.5.1 with Xcode 26.6, the disposable
[held-parent probe](held-parent-rename-probe.c) performed these steps:

1. Open the chosen root and its `dir` child by descriptor, and create `a.md`.
2. Move that same `dir` object outside the root, then put a symbolic link at
   the old `root/dir` path.
3. Stage new bytes through the held `dir` descriptor and exchange them with
   `a.md` using `renameatx_np(parentFD, ..., parentFD, ..., RENAME_SWAP)`.

Run from the repository root:

```sh
clang -Wall -Wextra -Werror planning/downstream/evidence/rooted-publication/held-parent-rename-probe.c -o /tmp/mt-f14-held-parent-probe
/tmp/mt-f14-held-parent-probe
```

Observed output: `held_parent_swap=succeeded outside_file=after`. The probe
used only a freshly created `/tmp` fixture and removed it on success; a
failed probe may leave only its private temporary fixture. It shows
that the exchange can change the moved file outside the approved root even
without traversing the new symbolic link. It does not prove the behavior of
every filesystem or macOS 26 patch version.

## Architecture decision needed before a production patch

The existing [E22 implementation contract](../../../epic-22-implementation.md)
records descriptor-anchored authority as carried forward, and
[EPIC_STANDARD §6](../../../EPIC_STANDARD.md) requires a stop when a document-
safety assumption proves false. A FileCore-owned rooted conditional-write API
would avoid the current check-then-path-use gap: validate relative components,
pin a physical root, open without following links, stage and exchange relative
to held descriptors, and preserve the existing revision, metadata, rollback,
recovery and no-exchange behavior. But the probe shows that a held parent
descriptor alone cannot certify root membership at publication.

The architecture review must identify an enforceable publication boundary or
explicitly resolve the residual outside-root race before implementation can
claim F14 acceptance. Rechecking ancestry immediately before `renameatx_np`
is not sufficient because the directory can move between the check and the
exchange. A failed post-write check cannot undo an outside-root mutation
safely. If the platform offers no suitable atomic operation, changing the
user-visible replacement or authority contract is a product decision, not an
implicit FileCore fallback.

Deterministic acceptance should swap an ancestor after the reviewed read and
before publication, leaving the outside file unchanged on refusal. It should
also cover a swapped final-file link, root replacement, ordinary nested files,
competing writers, metadata retention, rollback and a volume without exchange
support. Native permission and release evidence remain separate #115 gates.
