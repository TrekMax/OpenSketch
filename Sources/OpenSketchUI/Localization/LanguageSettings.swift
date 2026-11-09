import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        for language in preferredLanguages {
            let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized == "zh" || normalized.hasPrefix("zh-") {
                return "zh-Hans"
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return "en"
            }
        }
        return "en"
    }
}

@MainActor @Observable final class LanguageSettings {
    static let shared = LanguageSettings()
    static let storageKey = "appearance.language"

    private(set) var selection: AppLanguage
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: Self.storageKey)
        selection = storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var locale: Locale { Locale(identifier: selection.resolvedIdentifier()) }

    func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.storageKey)
        guard selection != language else { return }
        selection = language
        NotificationCenter.default.post(name: .applicationLanguageDidChange, object: nil)
    }
}

extension Notification.Name {
    static let applicationLanguageDidChange = Notification.Name("openSketch.applicationLanguageDidChange")
}
