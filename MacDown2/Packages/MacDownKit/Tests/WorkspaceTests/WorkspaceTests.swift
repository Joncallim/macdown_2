import Testing
@testable import Workspace

@Test func moduleLoads() {
    #expect(Workspace.moduleName == "Workspace")
}
