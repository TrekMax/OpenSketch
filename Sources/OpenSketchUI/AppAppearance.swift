import AppKit
import Observation

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "亮色"
        case .dark: "暗色"
        }
    }
}

@MainActor @Observable final class AppAppearance {
    private let defaults: UserDefaults
    var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: "appearanceMode")
            apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: "appearanceMode").flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    func apply() {
        NSApplication.shared.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
