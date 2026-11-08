import Foundation

/// Keep user values separate from translation keys so status text can change language in place.
indirect enum LocalizedMessage {
    case key(String)
    case value(String)
    case format(String, [LocalizedMessage])
    case error(Error)

    @MainActor func text(language: AppLanguage? = nil) -> String {
        switch self {
        case .key(let key): L10n.text(key, language: language)
        case .value(let value): value
        case .format(let key, let values): L10n.format(key, arguments: values.map { $0.text(language: language) }, language: language)
        case .error(let error): L10n.errorDescription(error, language: language)
        }
    }
}
