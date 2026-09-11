import Foundation

/// Small, real executable shell scripts written to a scratch directory per
/// test — real subprocess launches, not mocked (epic-14-implementation.md
/// §14's note that this evidence is not subject to the no-macOS-runtime
/// caveat that applies to on-device UI journeys).
enum TextFilterFixtures {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func makeExecutableScript(
        _ contents: String,
        named name: String = "\(UUID().uuidString).sh",
        in directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    static func makeNonExecutableFile(
        _ contents: String = "not a script",
        named name: String = "\(UUID().uuidString).txt",
        in directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Named scripts

    static let uppercase = "#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n"
    static let echoStdin = "#!/bin/sh\ncat\n"
    static let exitNonZero = "#!/bin/sh\necho 'something went wrong' >&2\nexit 7\n"
    static let sleepLong = "#!/bin/sh\nsleep 5\n"
    static let invalidUTF8Output = "#!/bin/sh\nprintf '\\377\\376'\n"
    static let printWorkingDirectory = "#!/bin/sh\npwd\n"

    static func oversizedOutput(bytes: Int) -> String {
        "#!/bin/sh\nyes A | head -c \(bytes)\n"
    }

    static let printSelectedEnvironment = """
    #!/bin/sh
    echo "PATH=$PATH"
    echo "DOC=$MACDOWN_DOCUMENT_PATH"
    echo "SEL=$MACDOWN_SELECTION_LENGTH"
    echo "SECRET=$MACDOWN_TEST_SECRET"
    """
}
