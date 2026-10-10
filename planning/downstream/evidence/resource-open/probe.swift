import Foundation
import Darwin

let flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
func attempt(_ label: String, _ rootFD: Int32, _ rel: String, expect: String) {
    let fd = openat(rootFD, rel, flags)
    var result: String
    if fd < 0 {
        result = "ERR errno=\(errno) (\(String(cString: strerror(errno))))"
    } else {
        var st = stat(); fstat(fd, &st)
        let regular = (st.st_mode & S_IFMT) == S_IFREG
        var bytes = ""
        if regular { var buf = [UInt8](repeating: 0, count: 64); let n = read(fd, &buf, 64); bytes = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : "" }
        result = "OK regular=\(regular) bytes=\(bytes.debugDescription)"
        close(fd)
    }
    let leaked = result.contains("OUTSIDE-SECRET")
    print("\(label): \(result) [expected \(expect)] \(leaked ? "!!LEAK!!" : "")")
}

let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ro-\(UUID().uuidString)")
let root = base.appendingPathComponent("root"), outside = base.appendingPathComponent("outside")
let fm = FileManager.default
try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
try fm.createDirectory(at: outside, withIntermediateDirectories: true)
try "inside-file".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
try "inside-sub".write(to: root.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
try "OUTSIDE-SECRET".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
try fm.createSymbolicLink(at: root.appendingPathComponent("link-out"), withDestinationURL: outside.appendingPathComponent("secret.txt"))
try fm.createSymbolicLink(at: root.appendingPathComponent("dir-out"), withDestinationURL: outside)
try fm.createSymbolicLink(at: root.appendingPathComponent("link-in"), withDestinationURL: URL(fileURLWithPath: "a.txt", relativeTo: root))
mkfifo(root.appendingPathComponent("fifo").path, 0o600)

let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
print("SDK/OS:", ProcessInfo.processInfo.operatingSystemVersionString)
attempt("positive a.txt", rootFD, "a.txt", expect: "OK inside-file")
attempt("positive sub/b.txt", rootFD, "sub/b.txt", expect: "OK inside-sub")
attempt("leaf symlink outside", rootFD, "link-out", expect: "ERR")
attempt("intermediate symlink outside", rootFD, "dir-out/secret.txt", expect: "ERR")
attempt("in-root symlink (NOFOLLOW_ANY)", rootFD, "link-in", expect: "ERR (hint resolves it first)")
attempt("dotdot escape", rootFD, "../outside/secret.txt", expect: "ERR")
attempt("dotdot via sub", rootFD, "sub/../../outside/secret.txt", expect: "ERR")
attempt("absolute path", rootFD, outside.appendingPathComponent("secret.txt").path, expect: "ERR")
attempt("fifo (nonblock)", rootFD, "fifo", expect: "OK regular=false (caller rejects) -- must not hang")

// Race: pin rootFD, then rename the root away and put a symlink to outside in its place.
let moved = base.appendingPathComponent("root-moved")
try fm.moveItem(at: root, to: moved)
try fm.createSymbolicLink(at: root, withDestinationURL: outside)
attempt("after root rename+symlink swap, pinned fd a.txt", rootFD, "a.txt", expect: "OK inside-file (pinned)")
attempt("after swap, secret via pinned fd", rootFD, "secret.txt", expect: "ERR (not in original root)")
// Race: intermediate directory replaced by outside symlink after pinning.
try fm.removeItem(at: root)
try fm.moveItem(at: moved, to: root)
let subFD = open(root.appendingPathComponent("sub").path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
try fm.moveItem(at: root.appendingPathComponent("sub"), to: root.appendingPathComponent("sub-away"))
try fm.createSymbolicLink(at: root.appendingPathComponent("sub"), withDestinationURL: outside)
attempt("fresh open through swapped intermediate", rootFD, "sub/secret.txt", expect: "ERR")
attempt("pinned sub fd b.txt", subFD, "b.txt", expect: "OK inside-sub")
close(subFD); close(rootFD)
try? fm.removeItem(at: base)
