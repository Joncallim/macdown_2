import AppKit

extension EditorTextSystem {
    struct PresentationViewport {
        let snapshot: EditorViewportSnapshot
        let revision: UInt64
        let selectedRanges: [NSValue]
        let markedRange: NSRange
        let scrollIdentity: ObjectIdentifier
    }

    /// Captures the same logical fragment/row used by external-reload preservation. A rapid second
    /// presentation update keeps the original anchor until user intent or a content revision supersedes it.
    public func preservingViewportForPresentationChange(_ change: () -> Void) {
        let retained = validPresentationViewport()
        cancelPresentationViewportRestoration()
        if let scrollView, textView.window != nil, pendingScrollOffset == nil {
            let snapshot = retained?.snapshot ?? viewportSnapshot()
            if snapshot.topVisibleUTF16Offset != nil {
                presentationViewport = PresentationViewport(
                    snapshot: snapshot, revision: editRevision, selectedRanges: textView.selectedRanges,
                    markedRange: textView.markedRange(), scrollIdentity: ObjectIdentifier(scrollView)
                )
                for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didLiveScrollNotification] {
                    presentationScrollObservers.append(NotificationCenter.default.addObserver(
                        forName: name, object: scrollView, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.cancelPresentationViewportRestoration() }
                    })
                }
            }
        }
        change()
        guard presentationViewport != nil else { return }
        textView.needsLayout = true
        let generation = presentationViewportGeneration
        presentationViewportTask = Task { @MainActor [weak self] in
            for _ in 0 ..< 2 {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, !Task.isCancelled, presentationViewportGeneration == generation else { return }
                restorePresentationViewportIfNeeded()
            }
            guard let self, presentationViewportGeneration == generation else { return }
            cancelPresentationViewportRestoration()
        }
    }

    /// Cancels on scroll intent rather than bounds changes: TextKit itself changes the bounds during layout.
    func cancelPresentationViewportRestoration() {
        let needsFinalPaint = presentationViewport != nil
        presentationViewportGeneration &+= 1
        presentationViewportTask?.cancel()
        presentationViewportTask = nil
        presentationViewport = nil
        presentationScrollObservers.forEach(NotificationCenter.default.removeObserver)
        presentationScrollObservers.removeAll()
        if needsFinalPaint {
            // Resolving an anchor can invalidate TextKit's rendering surfaces during a paint.
            // Once restoration retires, paint again without resolving any more fragments.
            textView.needsLayout = true
            textView.needsDisplay = true
        }
    }

    func restorePresentationViewportIfNeeded() {
        guard !isRestoringPresentationViewport else { return }
        guard let pending = validPresentationViewport() else {
            if presentationViewport != nil {
                cancelPresentationViewportRestoration()
            }
            return
        }
        isRestoringPresentationViewport = true
        defer { isRestoringPresentationViewport = false }
        let generation = presentationViewportGeneration
        _ = restoreViewportPosition(pending.snapshot, expandingFrame: true) {
            self.presentationViewportGeneration == generation && self.validPresentationViewport() != nil
        }
    }

    private func validPresentationViewport() -> PresentationViewport? {
        guard let pending = presentationViewport, let scrollView,
              !isDetachedFromEditorView, textView.window != nil,
              pending.revision == editRevision,
              pending.selectedRanges == textView.selectedRanges,
              pending.markedRange == textView.markedRange(),
              pending.scrollIdentity == ObjectIdentifier(scrollView)
        else { return nil }
        return pending
    }

    /// Shared restoration math for presentation changes and #119's disk-reload snapshot.
    /// Uses one source fragment, never a whole-document TextKit layout or selection/caret mutation.
    @discardableResult
    func restoreViewportPosition(_ snapshot: EditorViewportSnapshot, expandingFrame: Bool = false,
                                 ifCurrent: () -> Bool = { true }) -> Bool {
        guard let scrollView, let location = snapshot.topVisibleUTF16Offset,
              let frame = layoutFragmentFrame(atUTF16Location: location)
        else { return false }
        guard ifCurrent() else { return false }
        let rowOffset = snapshot.topVisibleFragmentOffset ?? 0
        let targetY = max(0, frame.minY + textView.textContainerInset.height + rowOffset)
        // TextKit can replace an estimated document height while resolving this fragment. The anchor must
        // have room before NSClipView constrains it, including the partially visible wrapped row.
        if expandingFrame, textView.frame.height < targetY + scrollView.contentView.bounds.height {
            textView.frame.size.height = targetY + scrollView.contentView.bounds.height
        }
        guard ifCurrent() else { return false }
        var origin = scrollView.contentView.bounds.origin
        let maximumY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        origin.y = min(targetY, maximumY)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }
}
