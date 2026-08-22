@testable import AppSettings
import Foundation
import Testing

@Suite("LegacyPreferencesDetector")
struct LegacyPreferencesDetectorTests {
    @Test func reportsTrueWhenTheSuiteHasAnyValue() {
        let suiteName = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }
        defaults.set(true, forKey: "someLegacyKey")

        #expect(LegacyPreferencesDetector.detect(suiteName: suiteName))
    }

    @Test func reportsFalseWhenTheSuiteExistsButIsEmpty() {
        let suiteName = UUID().uuidString
        guard UserDefaults(suiteName: suiteName) != nil else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { UserDefaults.standard.removeSuite(named: suiteName) }

        #expect(!LegacyPreferencesDetector.detect(suiteName: suiteName))
    }

    @Test func reportsFalseWhenTheSuiteWasNeverCreated() {
        let suiteName = "com.joncallim.macdown2.never-created-\(UUID().uuidString)"
        #expect(!LegacyPreferencesDetector.detect(suiteName: suiteName))
    }

    @Test func defaultSuiteNameMatchesTheOriginalMacDownBundleIdentifier() {
        #expect(LegacyPreferencesDetector.legacySuiteName == "com.uranusjr.macdown")
    }
}
