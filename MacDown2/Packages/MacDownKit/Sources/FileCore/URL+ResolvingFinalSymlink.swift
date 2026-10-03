import Darwin
import Foundation

public extension URL {
    /// `self`, with a symbolic link in the FINAL path component followed to the
    /// file it names (relative targets resolved against the link's directory).
    ///
    /// Documents are opened at the file a link points to: saving through
    /// `FileStore`'s replace-the-file publication would otherwise either refuse
    /// the link (`.notRegularFile`) or replace the link itself with a regular
    /// file. The link stays in place and the target's content is what is edited.
    /// A dangling link, a loop, or a non-link comes back unchanged. Only the last
    /// component is resolved — the path's directories keep their spelling.
    func resolvingFinalSymlink() -> URL {
        guard isFileURL else { return self }
        var current = standardizedFileURL
        for _ in 0 ..< 16 {
            var info = stat()
            guard lstat(current.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK,
                  let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)
            else { return current }
            let next = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : current.deletingLastPathComponent().appendingPathComponent(destination)
            current = next.standardizedFileURL
        }
        return standardizedFileURL // a loop: leave it for the open to refuse
    }
}
