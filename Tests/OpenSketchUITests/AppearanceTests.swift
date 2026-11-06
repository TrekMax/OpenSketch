import AppKit
import Testing
@testable import OpenSketchUI

@MainActor struct AppearanceTests {
    @Test func preferenceSurvivesRelaunchAndSystemClearsOverride() throws {
        let suite = "org.opensketch.tests.appearance.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let app = NSApplication.shared
        let previous = app.appearance
        defer {
            app.appearance = previous
            defaults.removePersistentDomain(forName: suite)
        }

        let settings = AppAppearance(defaults: defaults)
        #expect(settings.mode == .system)
        settings.mode = .dark
        #expect(app.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let relaunched = AppAppearance(defaults: defaults)
        #expect(relaunched.mode == .dark)
        relaunched.apply()
        #expect(app.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        relaunched.mode = .light
        #expect(app.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        relaunched.mode = .system
        #expect(app.appearance == nil)
        #expect(AppAppearance(defaults: defaults).mode == .system)
    }

    @Test func unknownPreferenceFallsBackToSystem() throws {
        let suite = "org.opensketch.tests.appearance.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unsupported-appearance", forKey: "appearanceMode")
        #expect(AppAppearance(defaults: defaults).mode == .system)
    }
}
