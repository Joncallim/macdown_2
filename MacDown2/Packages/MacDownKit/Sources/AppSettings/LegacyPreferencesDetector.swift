import Foundation

/// O3 — detects whether the original MacDown's preferences exist on this
/// Mac. Detection-only: no key is read and no value is copied or imported;
/// only presence/absence of the legacy `UserDefaults` domain is reported.
/// Building the actual key-by-key migration map is deferred, real work this
/// epic explicitly chose not to fold in (epic-13-implementation.md §18 O3,
/// §2.2). Offline/local only — a `UserDefaults` domain check, nothing else
/// (D9, §4 invariant 7).
public enum LegacyPreferencesDetector {
    /// The original MacDown's bundle identifier, and therefore its
    /// `UserDefaults` suite name.
    public static let legacySuiteName = "com.uranusjr.macdown"

    /// Whether `suiteName` has any persisted value at all. `suiteName` is
    /// overridable so tests can point this at an isolated suite instead of
    /// the real legacy domain (epic-13-implementation.md §14).
    ///
    /// Reads `persistentDomain(forName:)` — the named domain's own contents
    /// — rather than `UserDefaults(suiteName:).dictionaryRepresentation()`:
    /// the latter merges the entire search list (`NSArgumentDomain`,
    /// `NSGlobalDomain`, …), so it is non-empty even for a suite name that
    /// was never created, making the check always report `true`.
    public static func detect(suiteName: String = legacySuiteName) -> Bool {
        guard let domain = UserDefaults.standard.persistentDomain(forName: suiteName) else { return false }
        return !domain.isEmpty
    }
}
