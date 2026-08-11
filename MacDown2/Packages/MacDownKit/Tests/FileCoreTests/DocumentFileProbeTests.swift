@testable import FileCore
import Foundation
import Testing

@Test func moveProbePrefiltersLargeSiblingDirectoryByPhysicalMetadata() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = directory.appendingPathComponent("original.md")
    try "moved".write(to: original, atomically: true, encoding: .utf8)
    let prior = try FileStore().readSnapshot(from: original).revision.fileObjectID
    let moved = directory.appendingPathComponent("moved.md")
    try FileManager.default.linkItem(at: original, to: moved)
    try FileManager.default.removeItem(at: original)
    for index in 0 ..< 10000 {
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("sibling-\(index).md").path,
            contents: Data("unrelated".utf8)
        )
    }
    let clock = ContinuousClock()
    let start = clock.now
    let observation = await DocumentFileProbe().observe(expectedURL: original, priorFileObjectID: prior)
    let elapsed = start.duration(to: clock.now)

    let expected = try FileStore().readSnapshot(from: moved)
    #expect(observation == .moved(expected))
    #expect(elapsed < .seconds(2))
}
