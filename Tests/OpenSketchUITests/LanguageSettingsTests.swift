import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct LanguageSettingsTests {
    @Test func languageSelectionPersistsAndSystemFallsBackToEnglish() {
        let name = "openSketch.language.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults)
        #expect(settings.selection == .system)
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN", "en"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB"]) == "en")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR"]) == "en")
        settings.select(.simplifiedChinese)
        #expect(LanguageSettings(defaults: defaults).selection == .simplifiedChinese)
        defaults.set("unknown", forKey: LanguageSettings.storageKey)
        #expect(LanguageSettings(defaults: defaults).selection == .system)
    }

    @Test func explicitTranslationsAndFormatsPreserveUserText() {
        #expect(L10n.text("设置…", language: .english) == "Settings…")
        #expect(L10n.text("设置…", language: .simplifiedChinese) == "设置…")
        let filename = "设置… 100% 中文 👩🏽‍💻.png"
        #expect(L10n.format("已导出 %@", filename, language: .english) == "Exported \(filename)")
        #expect(L10n.format("已导出 %@", filename, language: .simplifiedChinese) == "已导出 \(filename)")
        #expect(L10n.text("unknown.key", language: .english) == "unknown.key")
        #expect(L10n.errorDescription(DocumentCodecError.unsupportedVersion(42), language: .english).contains("42"))
        #expect(!L10n.errorDescription(EditorError.invalid("名称不能为空。"), language: .english).contains("名称"))
    }

    @Test func catalogsHaveMatchingKeysAndFormatArguments() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let url = try #require(L10n.resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let data = try Data(contentsOf: url)
            return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let en = try catalog("en"), zh = try catalog("zh-Hans")
        #expect(en.count > 150)
        #expect(Set(en.keys) == Set(zh.keys))
        let pattern = try NSRegularExpression(pattern: "%[0-9$.*]*[dfl@]")
        func placeholders(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for key in en.keys {
            #expect(placeholders(en[key]!) == placeholders(zh[key]!))
            #expect(!en[key]!.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "English value for \(key)")
        }
    }

    @Test func changingLanguageRefreshesPresentationWithoutEditingDocument() throws {
        _ = NSApplication.shared
        let language = LanguageSettings.shared
        let saved = UserDefaults.standard.object(forKey: LanguageSettings.storageKey)
        let previous = language.selection
        defer {
            language.select(previous)
            if let saved { UserDefaults.standard.set(saved, forKey: LanguageSettings.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageSettings.storageKey) }
        }
        language.select(.simplifiedChinese)
        let controller = AppController()
        let oldMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = oldMenu }
        controller.makeMenus()
        let node = DesignNode(name: "设置…", kind: .text, text: "文字 English 100%")
        controller.session.document.pages[0].nodes = [node]
        controller.session.selection = [node.id]
        let coordinator = NativeLayerTree.Coordinator(session: controller.session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let item = try #require(coordinator.items[node.id])
        let row = tree.row(forItem: item)
        let cell = try #require(tree.view(atColumn: 0, row: row, makeIfNecessary: true) as? LayerTreeCell)
        let canvas = CanvasView(session: controller.session)
        let document = controller.session.document
        let before = try DocumentCodec.encode(document)
        let title = controller.workspace.current.title
        controller.session.setMessage(.format("已导出 %@", [.value("设置….png")]))
        language.select(.english)
        controller.refreshLanguage()
        coordinator.update()
        canvas.refreshLanguage()
        #expect(controller.session.message == "Exported 设置….png")
        #expect(controller.workspace.current.title != title)
        #expect(controller.workspace.current.title == "Untitled 1")
        #expect(NSApp.mainMenu?.item(at: 0)?.submenu?.items.contains { $0.title == "Settings…" && $0.keyEquivalent == "," } == true)
        #expect(try DocumentCodec.encode(controller.session.document) == before)
        #expect(controller.session.selection == [node.id])
        #expect(controller.session.selected?.text == "文字 English 100%")
        #expect(EditorTool.text.rawValue == "text")
        #expect(EditorTool.text.title == "Text")
        #expect(LayerCommand.group.title == "Group")
        #expect(AppearanceMode.dark.title == "Dark")
        #expect(cell.textField?.stringValue == "设置…")
        #expect(tree.view(atColumn: 0, row: row, makeIfNecessary: true) === cell)
        #expect(canvas.accessibilityLabel() == "Design canvas")
        language.select(.simplifiedChinese)
        #expect(controller.session.message == "已导出 设置….png")
        #expect(EditorTool.text.title == "文字")
    }

    @Test func settingsWindowIsReusedAndSharesAppearance() throws {
        _ = NSApplication.shared
        let name = "openSketch.settings.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let appearance = AppAppearance(defaults: defaults)
        let settings = SettingsWindowController(appearance: appearance)
        settings.showWindow(nil)
        let first = try #require(settings.window)
        defer { first.close() }
        #expect(first.contentView != nil)
        #expect(first.contentMinSize.width >= 600)
        settings.close()
        settings.showWindow(nil)
        #expect(settings.window === first)
        #expect(settings.appearance === appearance)
    }

    @Test func closingSettingsDoesNotCloseTheCurrentDocument() throws {
        _ = NSApplication.shared
        let controller = AppController()
        controller.workspace.newDocument()
        let ids = controller.workspace.documents.map(\.id)
        let current = controller.workspace.currentID
        controller.showSettings(nil)
        let settings = try #require(controller.settingsController?.window)
        defer { settings.close() }
        #expect(settings.identifier?.rawValue == "settings.window")
        controller.closeFocusedWindow(settings)
        #expect(!settings.isVisible)
        #expect(controller.workspace.documents.map(\.id) == ids)
        #expect(controller.workspace.currentID == current)
    }

    @Test func settingsDoesNotOfferBackgroundDocumentEditing() throws {
        _ = NSApplication.shared
        let controller = AppController()
        let node = DesignNode(kind: .rectangle)
        let sibling = DesignNode(kind: .ellipse)
        controller.session.change { $0.pages[0].nodes = [node, sibling] }
        controller.session.selection = [node.id, sibling.id]
        controller.showSettings(nil)
        let settings = try #require(controller.settingsController?.window)
        defer { settings.close() }
        for action in [#selector(AppController.undo(_:)), #selector(AppController.duplicate(_:)), #selector(AppController.performLayerCommand(_:))] {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.representedObject = LayerCommand.group
            #expect(controller.validateMenuItem(item, focusedWindow: nil))
            #expect(!controller.validateMenuItem(item, focusedWindow: settings))
        }
    }
}
