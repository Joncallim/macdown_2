import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("SidebarSection reconcile")
struct SidebarSectionOrderTests {
    @Test func reconcileEmptyReturnsDefaultOrder() {
        let order = SidebarSection.reconcile([])
        #expect(order == SidebarSection.defaultOrder)
    }

    @Test func reconcileIgnoresUnknownIDs() {
        let order = SidebarSection.reconcile(["unknown", "folder"])
        #expect(order == [.folder, .outline])
    }

    @Test func reconcileDeduplicatesIDs() {
        let order = SidebarSection.reconcile(["folder", "folder", "outline", "outline"])
        #expect(order == [.folder, .outline])
    }

    @Test func reconcileAppendsMissingCases() {
        let order = SidebarSection.reconcile(["outline"])
        #expect(order == [.outline, .folder])
    }

    @Test func reconcilePreservesPartialReverse() {
        let order = SidebarSection.reconcile(["outline", "folder"])
        #expect(order == [.outline, .folder])
    }

    @Test func reconcileIsIdempotent() {
        let input = ["outline", "folder"]
        let first = SidebarSection.reconcile(input)
        let second = SidebarSection.reconcile(first.map(\.rawValue))
        #expect(first == second)
    }
}
