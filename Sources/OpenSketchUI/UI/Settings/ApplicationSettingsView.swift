// Adapted from Compositor (f6cd2f0), Copyright (c) 2026 Wonder Assembly LLC.
// MIT License; see LICENSES/Compositor-MIT.txt and THIRD_PARTY_NOTICES.md.

import SwiftUI

struct ApplicationSettingsView: View {
    @Bindable var appearance: AppAppearance
    @Bindable var language: LanguageSettings

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List {
                Label(L10n.text("通用"), systemImage: "gearshape")
                    .listRowBackground(Color.accentColor.opacity(0.12))
                    .accessibilityIdentifier("settings.general")
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.text("设置"))
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
            .accessibilityIdentifier("settings.sidebar")
        } detail: {
            Form {
                Section {
                    Picker(L10n.text("外观"), selection: $appearance.mode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text(L10n.text("外观"))
                }
                Section {
                    Picker(L10n.text("语言"), selection: Binding(get: { language.selection }, set: { language.select($0) })) {
                        Text(L10n.text("跟随系统")).tag(AppLanguage.system)
                        Text(verbatim: "English").tag(AppLanguage.english)
                        Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                    }
                    .accessibilityIdentifier("settings.language")
                } header: {
                    Text(L10n.text("语言"))
                } footer: {
                    Text(L10n.text("更改立即生效并自动保存。"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.text("通用"))
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, language.locale)
        .frame(minWidth: 640, minHeight: 360)
    }
}
