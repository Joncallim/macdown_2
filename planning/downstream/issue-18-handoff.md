# Issue #18 / Epic 17 — Stateful release, signing, updates and CLI

## Owner summary

Package the completed editor as an installable, updatable Mac product without losing the state accumulated in development or legacy MacDown. Finish the promised CLI, prove real signed updates with meaningful user data, and promote only the exact artifact whose UI, localization and security evidence passed. Distribution is not permission to add a late unreviewed first-run experience.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, reviewed 2026-09-24. This is deferred architecture outside Claude's E22 work. Public branding direction is MostlyText, but exact final bundle/update/CLI/domain identifiers remain inputs to the earlier identity re-freeze, not guesses here. E23 owns final icon/Finder/Quick Look identity; #53 owns legacy preference conversion; this issue owns development-state migration, application startup integration, CLI and release infrastructure.

## Baseline reconciliation

Read #18, #115 and its latest audit comment, RELEASE_HARDENING, project.yml, AppDelegate, WorkspaceSession and the CLI main.swift. The CLI currently implements only registry-backed formats output and otherwise prints a placeholder. It does not yet implement open, stdin or --wait.

AppDelegate creates session/recovery/settings controllers during init, before any migration barrier. Production session storage uses Application Support/MacDown 2/session.json; defaults are under the interim app identity and the first-run key contains com.joncallim.macdown2. WorkspaceSession is schema version 1 and its convenience loader returns nil for missing, malformed or unknown versions. Migration must distinguish those cases by inspecting bytes, not treat nil as permission to overwrite unknown authoritative state. E23 adds authoritative custom themes. Some package dependencies use branches; final release resolution must be locked and audited rather than silently updated during archive.

Primary upstream release inspection on 2026-09-24 found Sparkle 2.10.0, published 2026-09-13, as the latest non-prerelease. Start integration pinned to 2.10.0 and its verified distribution/checksum; recheck security fixes when the implementation baseline is frozen. Do not use a floating 2.x range or an old version merely because a previous plan mentioned Sparkle 2.

## Identity manifest and release topology

Create a versioned `ReleaseIdentity` manifest, consumed by project generation, app/extension/CLI resources, namespace migration and packaging scripts. Required actual values: public display name, app/Quick Look bundle IDs, supported UTIs/theme extension, CLI command and embedded path, defaults/App Support/recovery namespaces, support/repository URLs, HTTPS appcast/asset origin, update public key and supported OS/architecture claims. Store only public values. The manifest must fail validation for placeholders, mixed old/new identity or unknown migration namespaces.

The app remains the existing Developer-ID-distributed desktop application; do not impose a new main-app sandbox that breaks user-installed text filters. Quick Look retains its separate least-privilege sandbox from E23. Updater/helper entitlements follow the pinned Sparkle distribution, not broadly copied app entitlements. No Mac App Store, privileged custom installer or general remote-control service is introduced.

Bundle the signed CLI inside the app, for example Contents/Helpers/<frozen-command>. A user-installed symlink can point into the installed app so updates replace CLI/app together. Installation is an explicit user action and never overwrites an existing command or edits shell profiles automatically. Document a user-owned bin path and a separately explicit administrator-managed installation option; do not invoke sudo from the app or require elevated rights for normal CLI use.

## Development/beta namespace migration

Add an app-owned `ApplicationBootstrapCoordinator` with states inspecting, awaitingConsentIfNeeded, migrating, ready and recoveryRequired. Start final session/settings/theme/recovery writers and normal open/restore handling only after ready. Queue a bounded set of legitimate LaunchServices/CLI requests during bootstrap; do not lose them or let a placeholder-window cleanup task close a migration/first-run window. Change that cleanup to target known placeholder windows, not every window whose delegate is not WindowController.

Inject one `ApplicationStorageLocations` value into all stores; remove hardcoded namespace construction through narrow constructors, not a second state manager. Enumerate the actual final stores at implementation start and check every defaults key/path against the identity manifest. Classify:

- Authoritative: typed preferences, theme selections/custom theme files, workspace/sidebar state, recent roots/bookmarks/aliases, session/tab/cursor/selection/layout records, untitled/dirty recovery bytes and their epochs/redirects/pending publication records.
- Disposable: parsed/rendered/highlight caches, temporary renderer artifacts and stale CLI runtime sockets. They may rebuild, but cannot be used as a substitute for missing recovery content.
- Never imported as instructions: old executable filters/startup commands, updater feed/key overrides, arbitrary IPC requests or unknown serialized objects. User scripts may remain accessible in their original location, but are not run by migration.

Source namespaces are explicit allowlisted previous product identities, not a recursive scan of Application Support. Legacy original-MacDown preferences are a separate opt-in import through #53, not merged indiscriminately with development-state migration. Final deliberate destination values win. Missing final state can be seeded from one verified source installation. Multiple divergent source namespaces require an explicit selection/conflict report; timestamps alone do not decide which unsaved buffer to discard.

Use copy -> verify -> publish, never destructive move-first. Capture a read-only inventory of relative paths, file types, lengths, hashes, schema versions and identity relationships. Preserve original UUID/recovery epochs where valid. Copy authoritative bytes to a restricted sibling staging directory, validate checksums and cross-record references, then publish the new namespace through one small journaled activation record. Keep old namespaces and a recovery manifest until the new app has loaded and durably saved the migrated state successfully; initial migration never automatically deletes the old installation's authoritative data.

Existing final data must not be replaced wholesale. Merge only explicitly absent logical records; identical records deduplicate by exact identity/content. Conflicting records remain available as separate recovery branches with an explicit recovery choice. Unknown/future schemas or invalid encoding are preserved for diagnosis and block destructive adoption. A session load returning nil is not evidence of an empty session. Theme imports go through E23 validation, and missing/custom theme IDs fall back visibly without deleting the preserved custom bytes.

Acquire an exclusive migration coordinator lock for new-product processes. Older development apps do not necessarily honor that lock: detect a running old app and ask the user to close it rather than killing it. Observe source identity/digests before and after staging and again before activation. If source state changes, discard only the owned staging attempt and re-plan; do not claim the lock fences an unmodified old writer. The original namespace remains readable even after a later old-app launch, so no concurrent old write causes deletion of the only recovery copy.

Bookmarks are not assumed portable across bundle/signing/sandbox identities. Preserve their bytes and associated URLs, resolve them using the target app's actual authority, refresh only valid grants, and request reauthorization for unavailable roots. Never use a saved path as a substitute permission grant. A failed root does not hide or discard other restored documents/recovery buffers.

Journal every publication step with operation ID/schema and before/desired digest. On retry, verify already-published records and continue only unchanged planned writes; preserve unrelated destination changes. Rollback touches only transaction-owned, unchanged output. Disk-full, permission-denied, interrupted copy, malformed manifest and crashes at every boundary leave the old authoritative state intact and the new failure visible. Do not claim a set of UserDefaults/file writes is atomically transactional; reuse #53's per-domain provenance/replay rules.

## CLI behavior and transport

Create a small Foundation/Darwin value/protocol package shared by the app and CLI; app lifecycle effects stay in WindowCoordinator. Use pinned swift-argument-parser for command syntax. Preserve `formats` using FileFormatRegistry. Support explicit `open`, default file arguments, `--` for names resembling options/subcommands, `-` for stdin, --wait, --help and --version. Resolve relative paths against the caller's captured working directory, not the app's launch directory. Spaces, Unicode, newlines and shell metacharacters remain structured data, never shell interpolation.

Chosen transport: a per-user Unix-domain socket served by the already-running app, with bounded versioned frames. It supports result acknowledgements and document-lifetime waiting without polling preference files or using distributed notifications as trusted command storage. Place it in a verified owner-only runtime directory under the OS-provided per-user temporary location, with 0700 directory/0600 endpoint, no-follow creation, a short hashed bundle-identity name and a checked sockaddr_un path-length bound. Verify peer UID in both directions using supported Darwin peer credentials; no TCP listener or privilege escalation. This prevents other-user access, not arbitrary same-user code, which already has the normal user's authority. Do not claim this endpoint is a security sandbox against a hostile process under the same account.

The embedded CLI resolves its enclosing installed app and launches that exact verified app through NSWorkspace/LaunchServices when necessary. It does not search PATH for another app or execute a shell command. A protocol handshake includes version, application instance UUID, bundle/build identity and request UUID. Reject mismatches; report not installed, wrong app, launch failure or unsupported protocol clearly. Connect/handshake/open-ack phases have finite deadlines; --wait has no arbitrary short document-editing timeout.

Frame parsing happens on bounded background I/O, not MainActor. Initial limits: 64 KiB metadata, 32 files/request, 32 MiB streamed stdin, eight concurrently admitted requests and 128 wait subscribers. Reject length overflow, invalid UTF-8 where text is required, malformed JSON/frames, unsupported fields and duplicate request IDs with changed payloads. Stream stdin with a byte ceiling before allocating the complete buffer. Explicit stdin, or a nonterminal pipe with no file arguments, creates one untitled Markdown document; a bare interactive invocation opens/activates the ordinary new-document flow. Do not unexpectedly block reading a terminal.

The app converts admitted requests to existing safe open/new-document operations. Missing/unreadable files fail per path; do not create them silently. Standard input enters the normal editable/recovery-backed document path and is not written to a temp file that session restore later mistakes for a saved user document. Acknowledge stdin acceptance only after the authoritative document/recovery admission has succeeded. Original stdin bytes cannot disappear because a client disconnects.

An acknowledgement reports actual opened document lifetime IDs or per-path failures, not just 'launch requested'. --wait subscribes to those lifetimes, including an already-open document. Save As follows the logical document lifetime; changing its pathname does not complete the wait. Save alone does not finish it. A cancelled close sheet keeps waiting. A confirmed close/discard, or successful normal app termination after its existing safe persistence protocol, ends the corresponding lifetime. --wait is not an assertion that changes were saved to the original file.

Client SIGINT/disconnect removes only its subscription; it never closes windows or discards source. App crash/lost connection returns a nonzero unavailable result and does not silently relaunch/replay stdin. Deduplicate request UUIDs within one bounded live-app session; do not promise exactly-once replay across crashes. Multiple callers waiting on one document all receive terminal completion once. Cleanup expired clients/IDs and never retain a closed document because its former CLI is gone. Stable exit categories distinguish usage, input/open failure, application/protocol unavailability and interruption; machine-readable protocol codes stay stable while human-readable messages follow the localization policy.

## Sparkle and offline behavior

Use one app-owned SPUStandardUpdaterController initialized after bootstrap. Add its Check for Updates action and supported update preference copy before final E16. Explicitly disable optional system-profile reporting; document only the necessary update network requests. Core editing/preview/export stays offline and never puts document paths/content in appcast requests. Use Sparkle's established permission/automatic-check controls rather than covert checks during document opening.

Embed and sign Sparkle 2.10.0 plus its required nested helpers using its supported archive/export route. Set the frozen HTTPS SUFeedURL and public SUPublicEDKey. Keep the Ed25519 private key in a restricted signing identity/Keychain or approved CI secret, separate from the web host. Never pass the private key as a visible command-line argument, commit it, or copy it into logs/artifacts. Keys/certificates are operator-provisioned prerequisites, not fabricated test constants.

Use full updates for 1.0; omit deltas until independently justified and verified. Enable supported verification-before-extraction and signed-feed/release-note validation for the pinned version; sign after every final feed/notes edit. Any adopted key rotation must follow Sparkle's documented constraints and receive separate tests; do not rotate Apple and EdDSA identities simultaneously by habit. Bundle IDs and monotonically increasing CFBundleVersion values remain stable across successive updates. Appcast minimum OS reflects the app's macOS 26 requirement, not merely Sparkle's lower minimum.

Private verification uses an isolated test feed route with the SAME signed binaries and a documented supported test-account feed override; the production embedded URL is not rewritten after testing. Remove the override before verifying final public feed behavior. No beta/rehearsal item is published to the stable appcast until authorization.

## Build, signing and publication chain

Use a clean exact source ref with locked dependency resolution/toolchain and the final string-freeze digest. Fail if resolution changes lockfiles, identity values or source files. Generate the Xcode project from project.yml. Build each claimed architecture explicitly; the current arm64 CI does not prove universal/Intel runtime support. Advertise only the frozen, actually verified architecture set.

Archive/export the app via xcodebuild with Developer ID and Hardened Runtime, preserving nested helper/extension/CLI signatures and permissions. Audit entitlements separately for app, Quick Look and updater. Release must not carry debug injection/testability concessions or a disabled library-validation entitlement merely to make local unsigned testing work. WebKit's internal renderer needs do not justify broad native-process executable-memory exceptions.

Submit the distribution archive with notarytool using an operator-managed credential profile, require Accepted and inspect its log, staple/validate the app, then create the primary signed/notarized/stapled DMG with the app and Applications link. Produce the full-update archive from the final stapled app and generate its EdDSA signature/appcast only after its bytes are frozen. Record app/tree/CDHash, extension/CLI identity, archive/DMG hashes, signing/notary evidence, source/dependency/toolchain manifest and dSYMs. Verify final artifacts again after upload by downloading and hashing them. No re-sign/rebuild after GUI evidence without invalidating the affected artifact proof.

Never publish an appcast that points to missing or unverified assets. Upload immutable versioned artifacts/notes first, verify them, then atomically promote the appcast last. A failed publish leaves the previous stable feed usable. Retain prior known-good assets. An emergency correction uses a higher verified build number rather than silently replacing bytes at an existing signed URL or forcing a downgrade. Secret-bearing release jobs never run on untrusted pull requests.

## Executable gate sequencing, without a release waiver

Use the three phases in #115's hand-off: software/UI debt stabilized; final E16 freeze plus private exact-artifact verification; public RC/release promotion. E17 engineering (migration, CLI, updater integration and all in-app copy) belongs before the final freeze. Signing/notarization for a tightly controlled private verification candidate is evidence preparation, NOT production authorization or publication.

Before adopting these phases, reconcile their explicit wording in the canonical release/debt documents as one documentation change. Keep #115 open until every required final artifact/localization row passes. Once it closes, production authorization promotes the identical previously verified bytes; it does not rebuild them. The final promoted RC is therefore the exact artifact already exercised. Any changed byte/identity/entitlement/UI string or failed final check invalidates evidence and reopens the gate. Nothing in this hand-off authorizes a candidate while #115 is open or excuses a missing suitable Mac.

## Stateful rehearsal and test matrix

Use a real previously installed development/beta build, not a hand-assembled empty defaults domain alone. Populate settings, pinned/open documents, Unicode paths, recent roots/bookmarks/aliases, untitled dirty buffers, conflicting recovery branches, theme files/selections and representative caches. Inventory/hash authoritative state before migration. Install the private final-identity candidate, inspect every category, relaunch, retry migration and verify no duplicated/lost branch. Add malformed/future schemas, unavailable roots, disk-full/interruption and concurrent old-app detection cases.

Test original MacDown preference import separately through #53. Verify CLI cold/warm launch, multiple paths, open failure, pipe limits, --wait across Save As/close-cancel/normal quit/crash, interrupted clients, wrong-protocol/UID, malicious frame lengths, stale socket and simultaneous callers. The normal first-run screen must not swallow a queued file/CLI request or be replaced by a new English-only release screen.

Install two consecutive signed private candidate builds N and N+1 and perform a real Sparkle update N -> N+1 with representative state retained. Do not edit Info.plist after signing to fake an older version. Exercise tampered/truncated/wrong-signature archives, wrong bundle/build, bad feed/notes signatures, network interruption, read-only/translocated installation, permission denial and update cancellation while dirty documents exist. Sparkle relaunch must respect the app's existing safe termination/recovery protocol; cancelled termination cannot force-discard edits.

Run #88's actual public-UI, VoiceOver, export/PDF, Quick Look and non-English journeys against the exact signed/notarized artifact, including quarantine/Gatekeeper behavior on a clean supported Mac without bypassing security. Public README/screenshots/claims are checked against that evidence, including offline, format/TeX boundaries, neutral diagrams, accessibility limitations and supported hardware.

## Implementation order and stop conditions

1. Consume the identity manifest and final storage schema; implement/bootstrap-test non-destructive migration and #53 integration.
2. Implement CLI value protocol/transport and lifecycle tests, then real app/CLI integration.
3. Integrate pinned Sparkle and every in-app update/migration string. Complete this before final E16; no new onboarding design.
4. Build the guarded private verification/release scripts and exact-artifact manifests. Provision real credentials only through the authorized operator boundary.
5. Complete E16 and private clean/stateful/update/UI proof, close #115, then promote the same bytes only after release authorization.

Allowed areas: bootstrap/storage-location injection, existing state-store constructors and migration tests, CLI/package/transport glue, updater integration, project declarations, release scripts/docs/catalogs. No E22 implementation branch, source normalization, core recovery-state redesign, custom privileged updater or new product capabilities.

Self-review addressed eager store initialization before migration, unknown sessions treated as empty, concurrent old writers ignoring a new lock, nonportable bookmarks, stdin represented by ephemeral saved files, --wait bound to paths instead of lifetimes, cancelled clients closing documents, a symlinked CLI becoming stale after updates, signing-helper entitlements and testing one binary then publishing another. Accounts, final identifiers, real signing/update and interactive proof remain explicit execution prerequisites, not claimed completed work.

Primary references: https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0 ; https://sparkle-project.org/documentation/ ; https://sparkle-project.org/documentation/security-and-reliability/ ; https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution .
