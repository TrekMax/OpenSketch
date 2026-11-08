import SwiftUI
import OpenSketchCore

extension LayerCommand {
    static var ordering: [Self] { LayerOrder.allCases.map(Self.order) }
    static var alignment: [Self] { LayerAlignment.allCases.map(Self.align) }
    static var distribution: [Self] { LayerAxis.allCases.map(Self.distribute) }

    @MainActor var title: String { L10n.text(titleKey) }
    var titleKey: String {
        switch self {
        case .group: "编组"
        case .ungroup: "取消编组"
        case .order(.forward): "上移一层"
        case .order(.backward): "下移一层"
        case .order(.front): "置于顶层"
        case .order(.back): "置于底层"
        case .align(.left): "左对齐"
        case .align(.horizontalCenter): "水平居中"
        case .align(.right): "右对齐"
        case .align(.top): "顶对齐"
        case .align(.verticalCenter): "垂直居中"
        case .align(.bottom): "底对齐"
        case .distribute(.horizontal): "水平等距分布"
        case .distribute(.vertical): "垂直等距分布"
        }
    }

    var identifier: String {
        switch self {
        case .group: "layer.group"
        case .ungroup: "layer.ungroup"
        case .order(let order): "layer.order.\(order.rawValue)"
        case .align(let alignment): "layer.align.\(alignment.rawValue)"
        case .distribute(let axis): "layer.distribute.\(axis.rawValue)"
        }
    }

    var symbol: String {
        switch self {
        case .group: "square.3.layers.3d"
        case .ungroup: "square.3.layers.3d.slash"
        case .order(.forward): "square.2.layers.3d.top.filled"
        case .order(.backward): "square.2.layers.3d.bottom.filled"
        case .order(.front): "arrow.up.to.line"
        case .order(.back): "arrow.down.to.line"
        case .align(.left): "align.horizontal.left"
        case .align(.horizontalCenter): "align.horizontal.center"
        case .align(.right): "align.horizontal.right"
        case .align(.top): "align.vertical.top"
        case .align(.verticalCenter): "align.vertical.center"
        case .align(.bottom): "align.vertical.bottom"
        case .distribute(.horizontal): "distribute.horizontal"
        case .distribute(.vertical): "distribute.vertical"
        }
    }
}

struct LayerActionsView: View {
    @Bindable var session: EditorSession

    private func action(_ command: LayerCommand, iconOnly: Bool = false) -> some View {
        Button { session.perform(command) } label: {
            if iconOnly { Image(systemName: command.symbol).frame(maxWidth: .infinity, minHeight: 22) }
            else { Text(command.title) }
        }
        .disabled(!session.canPerform(command))
        .help(command.title)
        .accessibilityLabel(command.title)
        .accessibilityIdentifier(command.identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                action(.group, iconOnly: true)
                action(.ungroup, iconOnly: true)
                Spacer(minLength: 8)
                Menu(L10n.text("层级")) {
                    ForEach(LayerCommand.ordering, id: \.identifier) { action($0) }
                }.fixedSize().help(L10n.text("调整图层前后顺序"))
            }
            HStack(spacing: 3) {
                ForEach(LayerCommand.alignment + LayerCommand.distribution, id: \.identifier) {
                    action($0, iconOnly: true)
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 11)).controlSize(.small)
    }
}

/// The effective context selection is shared by capability checks and execution.
struct LayerCommandsMenu: View {
    @Bindable var session: EditorSession
    var rowID: UUID
    var rename: () -> Void

    private var selection: Set<UUID> { session.contextMenuSelection(for: rowID) }

    private func action(_ command: LayerCommand) -> some View {
        let target = selection
        return Button(command.title) {
            session.selection = target
            session.perform(command)
        }
        .disabled(!session.canPerform(command, selection: target))
        .accessibilityIdentifier(command.identifier)
    }

    var body: some View {
        Button(L10n.text("重命名"), action: rename)
            .accessibilityIdentifier("layer.rename")
        Button(L10n.text("复制图层")) { session.duplicateContextLayers(for: rowID) }
            .disabled(!session.canEditContextLayers(for: rowID))
            .accessibilityIdentifier("layer.duplicate")
        Button(L10n.text("删除")) { session.deleteContextLayers(for: rowID) }
            .disabled(!session.canEditContextLayers(for: rowID))
            .accessibilityIdentifier("layer.delete")
        Divider()
        action(.group)
        action(.ungroup)
        Divider()
        ForEach(LayerCommand.ordering, id: \.identifier) { action($0) }
        Menu(L10n.text("对齐")) { ForEach(LayerCommand.alignment, id: \.identifier) { action($0) } }
        Menu(L10n.text("等距分布")) { ForEach(LayerCommand.distribution, id: \.identifier) { action($0) } }
    }
}
