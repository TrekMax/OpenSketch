// Adapted from Compositor (f6cd2f0), Copyright (c) 2026 Wonder Assembly LLC.
// MIT License; see LICENSES/Compositor-MIT.txt and THIRD_PARTY_NOTICES.md.

import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first ?? "en"
    }
}

@MainActor @Observable final class LanguageSettings {
    static let shared = LanguageSettings()
    static let storageKey = "appearance.language"
    private(set) var selection: AppLanguage
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var locale: Locale { Locale(identifier: selection.resolvedIdentifier()) }

    func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.storageKey)
        guard selection != language else { return }
        selection = language
        NotificationCenter.default.post(name: .applicationLanguageDidChange, object: self)
    }
}

extension Notification.Name {
    static let applicationLanguageDidChange = Notification.Name("openSketch.applicationLanguageDidChange")
}
