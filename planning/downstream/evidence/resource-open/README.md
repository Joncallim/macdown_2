# RESOURCE-OPEN probe (issue #121, first executable unit)

`probe.swift` opens files with the exact flag set the #121 contract specifies, `openat(pinnedRootFD, relativePath, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH)`, against a real temporary tree containing an "outside" sentinel in a separate directory, and records the syscall result for each schedule. `result-macos-26.5.1.txt` is the retained output.

**What it establishes (macOS 26.5.1, SDK 26.5, arm64):** ordinary files open and read; outside leaf and intermediate symlinks fail with `ELOOP`; `..` and absolute paths fail with `ENOTCAPABLE`; a FIFO opens non-blocking (caller must still reject non-regular via `fstat`); after the root directory is renamed away and replaced by a symlink to the outside directory, the **pinned descriptor still reads only the original tree** and cannot reach the outside sentinel; a swapped intermediate directory fails fresh opens and the pinned sub-directory descriptor remains valid. No outside sentinel byte was returned.

**What it does not establish:** other macOS 26 patch levels or the minimum supported 26.0; barrier-driven replacement **between** the syscall's path walk steps (the schedules here swap before the open, relative to a pinned descriptor, not mid-walk); growth past the cap, cancellation and descriptor/scope baselines (these belong to the reader's tests, which do not exist yet); behaviour on non-APFS volumes. In-root symlinks are rejected by `O_NOFOLLOW_ANY` as designed, so the reader must resolve them with a canonical-target hint and then open strictly relative (a hint is not authorisation).

Re-run: `swiftc -O probe.swift -o probe && ./probe` and append the new host's result file. Do not edit a retained result.
