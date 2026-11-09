import Foundation
import OpenSketchCore

@MainActor enum L10n {
    static let resourceBundle: Bundle = locateResourceBundle()

    private static func locateResourceBundle() -> Bundle {
        if let url = Bundle.main.url(forResource: "OpenSketch_OpenSketchUI", withExtension: "bundle"),
           let installedBundle = Bundle(url: url) {
            return installedBundle
        }
        return Bundle.module
    }

    static var locale: Locale { LanguageSettings.shared.locale }

    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let catalog = catalog(for: language ?? LanguageSettings.shared.selection)
        return catalog?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg..., language: AppLanguage? = nil) -> String {
        format(key, arguments: arguments, language: language)
    }

    static func format(_ key: String, arguments: [CVarArg], language: AppLanguage? = nil) -> String {
        let selected = language ?? LanguageSettings.shared.selection
        return String(format: text(key, language: selected), locale: Locale(identifier: selected.resolvedIdentifier()), arguments: arguments)
    }

    private static func catalog(for language: AppLanguage) -> Bundle? {
        let identifier = language.resolvedIdentifier()
        guard let url = resourceBundle.url(forResource: identifier, withExtension: "lproj") else {
            return nil
        }
        return Bundle(url: url)
    }

    static func errorDescription(_ error: Error, language: AppLanguage? = nil) -> String {
        switch error {
        case EditorError.invalid(let key): return text(key, language: language)
        case EditorError.documentAlreadyOpen(let name):
            return format("“%@”已在另一个标签页中打开。请选择其他保存位置。", name, language: language)
        case DocumentCodecError.unsupportedFormat: return text("不支持此文档格式。", language: language)
        case DocumentCodecError.unsupportedVersion(let version):
            return format("此文档使用版本 %d，当前支持版本 %d。", version, DesignDocument.currentVersion, language: language)
        case DocumentCodecError.limitExceeded: return text("文档内容超出格式或大小限制", language: language)
        case DocumentCodecError.invalidContent, is DecodingError: return text("文档数据无效", language: language)
        case LayerEditError.invalidSelection: return text("请选择适用的图层", language: language)
        case LayerEditError.differentParents: return text("所选图层必须位于同一容器", language: language)
        case LayerEditError.lockedOrHidden: return text("图层或祖先已锁定 / 隐藏", language: language)
        case LayerEditError.styledGroup: return text("编组包含填充、描边或不透明度效果", language: language)
        case LayerEditError.invalidGeometry: return text("图层几何数据无效或超出范围", language: language)
        case is DocumentOperationError: return text("文档操作无效。", language: language)
        default:
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain {
                switch cocoa.code {
                case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return text("找不到文件。", language: language)
                case NSFileReadNoPermissionError: return text("没有读取此文件的权限。", language: language)
                case NSFileWriteNoPermissionError: return text("没有写入此位置的权限。", language: language)
                case NSFileWriteOutOfSpaceError: return text("磁盘空间不足。", language: language)
                default: break
                }
            }
            return error.localizedDescription
        }
    }
}
