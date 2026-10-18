# Stop HTML resource callbacks when their consumer is retired

## Owner outcome and boundary

Once WebKit stops an HTML resource task, it must receive no more bytes, success
or failure callbacks. The current synchronous handler can be stopped reentrantly
inside a response or data callback; synchronous execution does not make that
schedule impossible. This bounded correction revokes delivery before cancellation
and checks the exact task attempt before every callback. Replacing or disposing
the current request also retires its admitted consumers.

The inspected baseline is `6770251faa9fef1bd679bcd02854add59bb06717`. The accepted
[handoff](issue-121-handoff.md), EPIC_STANDARD and RELEASE_HARDENING remain binding.
This slice follows the navigation correction; it does not complete immutable
resource ownership or change folder permissions, resource reads or dependencies.

## Immutable-root prerequisite found during review

The current HTML view receives only FileDocument and infers its parent as a
resource root. PreviewSecurityScope constructs even when security-scope acquisition
returns false. Neither supplies an explicit directory grant. Opening that inferred
URL with DirectoryLease would pin an object without establishing permission.

An existing folder can originate from Open Folder, a resolved security bookmark,
or the explicit Open Parent Folder action. FileTreeModel.rootAccessURL exposes its
scope's URL, but not a preview capability or a retained scope owner. WorkspaceModel
also permits setting a folder association without proving that authority. Passing
either URL alone to preview would not settle the lifetime contract.

For nested documents, a workspace directory grant also needs a reviewed mapping
to the document-relative resource base. DirectoryLease currently opens a URL; it
cannot derive a child directory lease from an existing descriptor. Checking a
child pathname and then reopening it absolutely would reintroduce the race the
handoff forbids. Silently granting the document's parent, broadening root-relative
URLs to the entire workspace, or disabling all existing local assets is not this
bounded fix.

Therefore immutable-root integration stops at this prerequisite. The next design
must identify the app's explicit folder-grant owner and propagation/revocation
paths, retain its scope through actual I/O, and define a contained document-base
mapping. File-only and untitled loads use grant none for subresources while their
main source remains renderable. No new panel or permission workflow is added here.

## Delivery state and ownership

The MainActor handler keeps a bounded-by-active-tasks registry keyed by scheme-task
object identity. Each admission records the originating view identity and a fresh
operation token. Duplicate starts while an attempt is active are ignored. Stop
removes only that view's matching attempt and emits no callback. Request assignment
clears existing admission before replacement can cause callbacks.

Each synchronous start retains a local attempt value. Before response, data,
finish or failure, the registry must still match that token. Checks after response
and data account for reentrant stop, disposal, replacement and nested work. Success
and failure remove admission before their terminal callback. An older stack frame
cannot consume a replacement attempt using the same task object, and an unrelated
task or view cannot cancel the live attempt. No task history accumulates.

This registry controls delivery only. It neither cancels a blocking filesystem
read nor establishes worker, payload, scope or aggregate-quota settlement. The
mutable request, fixed authority and Foundation reopen remain known defects pending
the explicit-grant design. A delayed A task can still start after request B and
read B; that retained control must remain failing and must not be called fixed by
request-assignment revocation.

## Evidence and remaining gates

Use recording WKURLSchemeTask callbacks against the actual handler, first on the
unchanged baseline and then on the correction. Controls cover response/data stop,
repeated stop, wrong-view stop, independent tasks, nested reuse, duplicate active
start, request replacement/disposal, terminal reentrancy and ordinary MIME/CSP
delivery. These are ordered synthetic controls, not native WebKit scheduling or
network evidence. Retain the root-confusion observation separately.

Require independent source review, exact-head lint/format, affected package and
selected app checks, unsigned Release app/CLI and test-target compilation. Keep
the previous real WebKit main-document control. Heavy commands remain serial.
No performance rerun is justified by a callback-only change. Full immutable load
identity, contained-reader integration, off-main execution, quotas, native hostile
content, real scope balancing and minimum-macOS-26.0 evidence remain open. The
existing #53, #203, compliance, Pinyin coverage and owner-review gates also remain.
