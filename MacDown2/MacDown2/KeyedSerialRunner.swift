import Foundation

/// Runs async operations one at a time PER KEY, in submission order; operations with
/// different keys run concurrently. Used so two requests to open the same file — a
/// double-clicked sidebar row, a held Return, two quick Finder opens — cannot both pass
/// the "is it already open?" check before either has created its window (which produced
/// two live editors for one file).
@MainActor
final class KeyedSerialRunner<Key: Hashable> {
    private var tails: [Key: Task<Void, Never>] = [:]

    func run(key: Key, _ operation: @escaping @MainActor () async -> Void) async {
        let previous = tails[key]
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tails[key] = task
        await task.value
        if tails[key] == task {
            tails[key] = nil
        }
    }
}
