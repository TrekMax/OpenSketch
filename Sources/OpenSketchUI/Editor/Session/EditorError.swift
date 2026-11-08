import Foundation

enum EditorError: LocalizedError {
    case invalid(String)
    case documentAlreadyOpen(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let key): key
        case .documentAlreadyOpen(let name): "Document already open: " + name
        }
    }
}
