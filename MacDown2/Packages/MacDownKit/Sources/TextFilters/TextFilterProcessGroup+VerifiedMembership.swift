import Darwin
import Foundation

/// Fail-closed process-group membership inspection used by
/// `TextFilterProcessSession`'s completion/containment gate.
///
/// The original boolean `groupHasLiveMembers()` cannot distinguish an empty
/// group from a failed `sysctl(KERN_PROC_PGRP)` query: its helper returns an
/// empty array for both. At a containment boundary that ambiguity is unsafe —
/// "could not inspect" must never become "confirmed empty." This tri-state
/// API keeps the two outcomes distinct while the held zombie leader pins the
/// pid/pgid identity to this invocation.
extension TextFilterProcessGroup {
    enum MembershipState: Equatable {
        case empty
        case live
        case unconfirmed
    }

    /// Returns whether this invocation's initial process group has any live
    /// member, preserving process-table inspection failure as `.unconfirmed`
    /// instead of laundering it into `.empty`.
    func verifiedMembershipState() -> MembershipState {
        guard let pid else { return .empty }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, pid]
        let stride = MemoryLayout<kinfo_proc>.stride
        guard stride > 0 else { return .unconfirmed }

        for _ in 0 ..< 4 {
            var querySize = 0
            guard sysctl(&mib, u_int(mib.count), nil, &querySize, nil, 0) == 0,
                  querySize > 0
            else {
                // The leader is deliberately still present as a held zombie
                // until `reapLeader()`, so a successful zero-sized snapshot
                // is itself inconsistent with the identity we still own.
                return .unconfirmed
            }

            let capacity = querySize / stride + 8
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var bufferSize = capacity * stride
            let result = buffer.withUnsafeMutableBytes { raw in
                sysctl(&mib, u_int(mib.count), raw.baseAddress, &bufferSize, nil, 0)
            }
            guard result == 0 else {
                if errno == ENOMEM {
                    continue
                }
                return .unconfirmed
            }
            guard bufferSize.isMultiple(of: stride) else { return .unconfirmed }

            let count = bufferSize / stride
            guard count > 0 else { return .unconfirmed }
            return buffer[0 ..< count].contains { $0.kp_proc.p_stat != SZOMB } ? .live : .empty
        }

        return .unconfirmed
    }

    /// Configures the one parent-side descriptor whose writes can
    /// legitimately encounter `EPIPE`. This must succeed *before* the child
    /// is launched: otherwise a failed `F_SETNOSIGPIPE` leaves MacDown itself
    /// exposed to process-wide `SIGPIPE` termination while the background
    /// stdin writer is active.
    func configureParentStdinWriteDescriptor(_ pipes: StandardStreamPipes) throws {
        let descriptor = pipes.stdin.fileHandleForWriting.fileDescriptor
        guard fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw SpawnError.posixError(errno, step: "fcntl(F_SETNOSIGPIPE)")
        }
    }
}
