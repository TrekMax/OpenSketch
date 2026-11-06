# OpenSketchCore API（原型 v1）

Swift 6 语言模式；macOS 15+。只有 Foundation / CoreGraphics 系统依赖。核心值模型不隔离到 MainActor，公开持久化值类型均为 Codable、Equatable、Sendable；文档、页面、节点另实现 Identifiable，标识为 UUID。UI 持有并修改文档值。

## 值模型

以下是最终公开字段和初始化器（属性均为可写 var，常量另标明）。

```swift
enum NodeKind: String, Codable, CaseIterable, Sendable {
    case frame, group, rectangle, ellipse, text, path
}
enum ParagraphAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right, justified
}
struct RGBAColor: Codable, Equatable, Sendable {
    var red, green, blue, alpha: Double
    init(red: Double, green: Double, blue: Double, alpha: Double = 1)
    static let black: RGBAColor
    static let white: RGBAColor
}
struct NodeStyle: Codable, Equatable, Sendable {
    var fill: RGBAColor?
    var stroke: RGBAColor?
    var strokeWidth: Double
    var opacity: Double
    var cornerRadius: Double
    init(fill: RGBAColor? = nil, stroke: RGBAColor? = nil,
         strokeWidth: Double = 1, opacity: Double = 1, cornerRadius: Double = 0)
    static func `default`(for kind: NodeKind) -> NodeStyle
}
enum PathCommand: Codable, Equatable, Sendable {
    case move(to: CGPoint)
    case line(to: CGPoint)
    case cubic(control1: CGPoint, control2: CGPoint, to: CGPoint)
    case close
}
struct VectorPath: Codable, Equatable, Sendable {
    var commands: [PathCommand]
    init(commands: [PathCommand] = [])
}
struct DesignNode: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var kind: NodeKind
    var frame: CGRect
    var rotation: Double
    var isVisible: Bool
    var isLocked: Bool
    var clipsContent: Bool
    var style: NodeStyle
    var text: String
    var fontName: String
    var fontSize: Double
    var textAlignment: ParagraphAlignment
    var path: VectorPath
    var children: [DesignNode]

    init(id: UUID = UUID(), name: String = "", kind: NodeKind,
         frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
         rotation: Double = 0, isVisible: Bool = true, isLocked: Bool = false,
         clipsContent: Bool = false, style: NodeStyle? = nil,
         text: String = "", fontName: String = "Helvetica Neue", fontSize: Double = 24,
         textAlignment: ParagraphAlignment = .left,
         path: VectorPath = VectorPath(), children: [DesignNode] = [])

    func cloned() -> DesignNode
}
struct DesignPage: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var size: CGSize
    var nodes: [DesignNode]
    init(id: UUID = UUID(), name: String = "页面 1",
         size: CGSize = CGSize(width: 1440, height: 900), nodes: [DesignNode] = [])
}
struct DesignDocument: Codable, Equatable, Identifiable, Sendable {
    static let formatIdentifier: String // "org.opensketch.document"
    static let currentVersion: Int     // 1
    var format: String
    var version: Int
    var id: UUID
    var name: String
    var pages: [DesignPage]
    init(id: UUID = UUID(), name: String = "未命名", pages: [DesignPage] = [DesignPage()],
         format: String = Self.formatIdentifier, version: Int = Self.currentVersion)
    static func blank() -> DesignDocument
}
```

`blank()` 有一个空白页面。默认填充：frame 白色、text 黑色、rectangle/ellipse/path 蓝色（0.27, 0.48, 0.95）；group 无填充。默认均无描边。`cloned()` 复制全部值并给自身和全部后代分配新 UUID。普通修改应保留 UUID。仅 frame 和 group 接受 children。

## 递归树操作

```swift
extension DesignDocument {
    func node(id: UUID) -> DesignNode?
    func pageContaining(nodeID: UUID) -> UUID?
    func parentID(of nodeID: UUID) -> UUID?
    @discardableResult
    mutating func updateNode(id: UUID, _ update: (inout DesignNode) -> Void) -> Bool
    mutating func insertNode(_ node: DesignNode, into pageID: UUID,
                             parentID: UUID? = nil, at index: Int? = nil) throws
    @discardableResult
    mutating func removeNode(id: UUID) -> DesignNode?
}
enum DocumentOperationError: Error, Equatable {
    case pageNotFound, parentNotFound, invalidParent, invalidIndex, duplicateID
}
```

children/nodes 从底到顶排序。insert 的 nil 索引表示追加到最顶；nil parentID 表示页面根节点。指定父节点必须属于目标页且为 frame/group；整个插入子树的 ID 不能与现有文档/页面/节点或自身重复。失败不改变文档。remove 返回包含全部后代的原节点。update 对首个匹配节点应用闭包，未找到返回 false；调用者负责修改值的有效性，统一在保存时验证。父查找对根节点和未找到都返回 nil，可结合 node(id:) 区分。操作本身不阻止显式修改锁定节点；UI 应用祖先锁定/可见约束。

## 图层组织与排版

```swift
enum LayerOrder: String, CaseIterable, Sendable {
    case forward, backward, front, back
}
enum LayerAlignment: String, CaseIterable, Sendable {
    case left, horizontalCenter, right, top, verticalCenter, bottom
}
enum LayerAxis: String, CaseIterable, Sendable { case horizontal, vertical }
enum LayerCommand: Equatable, Sendable {
    case group, ungroup
    case order(LayerOrder), align(LayerAlignment), distribute(LayerAxis)
}
struct LayerEditResult: Equatable, Sendable {
    var document: DesignDocument
    var selection: Set<UUID>
    init(document: DesignDocument, selection: Set<UUID>)
}
enum LayerEditError: Error, Equatable {
    case invalidSelection, differentParents, lockedOrHidden, styledGroup, invalidGeometry
}
enum LayerEditing {
    static func canApply(_ command: LayerCommand, to document: DesignDocument,
                         pageID: UUID, selection: Set<UUID>) -> Bool
    static func apply(_ command: LayerCommand, to document: DesignDocument,
                      pageID: UUID, selection: Set<UUID>) throws -> LayerEditResult
}
```

命令是纯值变换，失败不修改输入。全部选中 ID 必须属于指定页；选中父子项时只处理最外层选中根。任一有效根或其祖先锁定/隐藏会阻止整个命令，不能静默过滤成子集。选中可编辑父容器时，其锁定/隐藏后代仍作为内容保留。

编组要求至少两个同父根；取消编组要求至少一个同父 group；重排要求至少一个同父根。对齐至少两个根、分布至少三个根，允许同页跨父容器。编组在父坐标中取旋转 frame 的包围盒，子层原点减去组原点，保留原 UUID、rotation 和子树。新组放在原最前选中层的位置，未选中项彼此顺序保持不变。取消编组将子层中心应用组的局部变换，累加旋转并保持尺寸；带 fill、stroke 或 opacity != 1 的组被拒绝，以免丢失合成外观。

叠放数组仍从底到顶。置顶/置底使用稳定分区，上移/下移让每段选中层跨过一个相邻未选中层；边缘无变化返回相同文档。对齐以所有选中根的页面轴向包围盒并集为目标；包围盒取变换后的 frame 四角，不包含描边。将页面位移通过父变换的逆矩阵换算为局部位移，因此支持旋转父容器。

分布按空间位置稳定排序，使相邻包围盒之间的间隙相等，固定排序首尾节点，允许负间隙；同坐标按原绘制顺序决胜。group 使用自身存储的 frame，本阶段没有整体缩放或子层变化后自动重算编组边界。

`canApply` 是不分配新 UUID、不编码的资格预检，检查选择、可编辑性、操作几何及编组的深度/节点数。它不保证字符串、路径或最终编码体积等全部格式限制通过。`apply` 验证输入并以 `DocumentCodec.encode` 验证结果；因此最终仍可能抛出 `DocumentCodecError`。UI 先结束活动输入，只在文档实际变化时提交一次历史事务，再应用返回的 selection；无效或无变化命令不新增文档历史。

## 坐标与命中

```swift
enum SceneGeometry {
    static func localTransform(for node: DesignNode) -> CGAffineTransform
    static func worldTransform(id: UUID, in page: DesignPage) -> CGAffineTransform?
    static func hitTest(_ point: CGPoint, in page: DesignPage) -> UUID?
    static func traversal(in page: DesignPage) -> [DesignNode]
    static func cgPath(for path: VectorPath) -> CGPath
}
```

frame.origin 是父坐标中的位置，frame.size 是本地宽高。本地原点为 (0,0)。rotation 是角度制，向下为正的画布中正角度顺时针。变换是 `T(frame.origin) × T(center) × R(rotation) × T(-center)`；CoreGraphics 合成时子变换使用 `local.concatenating(parentWorld)`。绘制、导出、命中需使用这一规则；视图缩放和平移在世界坐标外单独处理。

traversal 是父先于孩子、每层从底到顶的完整绘制顺序，保留隐藏和锁定节点供图层面板使用。渲染时仍需按树维持祖先变换、可见性、透明度及裁剪。worldTransform 查找忽略可见/锁定状态，未找到返回 nil。

hitTest 输入页面世界坐标，从顶到底检查子树、孩子先于父节点，返回最深可选 UUID。隐藏或锁定祖先阻断整棵子树。clipsContent 仅在 frame 上生效，按 frame 本地矩形边界裁剪；不裁剪的父节点外仍可命中孩子。ellipse 按椭圆、rectangle 按圆角轮廓、path 按非零绕数填充和实际描边命中；路径描边可超出 frame。frame/group/text 按本地矩形命中。透明度与颜色 alpha 不作为编辑命中的可见性开关。描边使用 butt 端点、miter 连接与 miterLimit 10，UI 共享此设置。

## 历史与保存状态

```swift
struct DocumentHistory: Sendable {
    init(document: DesignDocument)
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var isEditing: Bool { get }
    mutating func begin(document: DesignDocument)
    @discardableResult mutating func commit(document: DesignDocument) -> Bool
    mutating func cancel() -> DesignDocument?
    mutating func undo(current: DesignDocument) -> DesignDocument?
    mutating func redo(current: DesignDocument) -> DesignDocument?
    mutating func markSaved(document: DesignDocument)
    func isDirty(_ document: DesignDocument) -> Bool
}
```

每次拖动/文本编辑开始时 begin，过程中直接改文档，结束 commit；一个事务形成一个撤销条目。重复 begin 保留首次起点。取消必须把 cancel 返回的原文档赋回 UI。无变化的 commit 返回 false 并保留 redo；有变化提交清空 redo。无事务的 commit 返回 false。活动事务期间 canUndo/canRedo 为 false，undo/redo 返回 nil；UI 应先结束或取消活动编辑。

init 将初始文档作为已保存快照。新建未命名空文档初始为干净；UI 如需提示未命名状态应单独管理 URL。只在 DocumentCodec.save 成功后调用 markSaved；保存不清空 undo。isDirty 比较当前完整值与最近成功保存快照，包含未提交的编辑；撤销回保存内容变干净，重做离开又变脏。即使手势中保存再取消，也依据实际已保存内容判断。没有条目时 undo/redo 返回 nil。快照使用 Swift 值语义/COW，目前没有历史长度上限。

## 原生包与验证

```swift
enum DocumentCodec {
    static let maximumDataBytes: Int       // 16 MiB
    static let maximumNodeCount: Int       // 50,000 (全部页面合计)
    static let maximumDepth: Int           // 64 (根节点深度 1)
    static let maximumPathCommands: Int    // 200,000 (全部节点合计)
    static let maximumPageCount: Int       // 128
    static let maximumStringBytes: Int     // 每个字符串 1 MiB UTF-8
    static func encode(_ document: DesignDocument) throws -> Data
    static func decode(_ data: Data) throws -> DesignDocument
    static func save(_ document: DesignDocument, to url: URL) throws
    static func load(from url: URL) throws -> DesignDocument
}
enum DocumentCodecError: Error, Equatable {
    case unsupportedFormat
    case unsupportedVersion(Int)
    case invalidContent(String)
    case limitExceeded(String)
}
```

`.opensketch` 为目录包，仅存 `document.json`（JSONEncoder，prettyPrinted + sortedKeys）。编码前验证全部值；解码先验证字节量及 JSON 嵌套上限（208，忽略字符串中的括号），再解码并验证树。保存先完成验证/编码，随后用 Foundation FileWrapper `.atomic` 写包替换，支持首次创建和覆盖。加载拒绝包/JSON 符号链接，先检查文件大小，再按 64 KiB 有界读取。错误由上述枚举、JSONDecoder 或 Foundation 文件错误抛出，UI 应呈现本地化错误。

拒绝未知格式、任何非 v1 版本、空页面列表、重复 UUID（文档/页面/全部节点统一空间）、非法枚举/缺字段、叶节点 children、非法路径顺序、非有限数字。位置/路径坐标限定 ±1e9；节点宽高 0...1e7；页面宽高 0.1...1e7；旋转 ±1e9 度；字号 0.1...1e5；描边宽 0...1e5；圆角 0...1e7；颜色/透明度 0...1。路径非空时必须以 move 开始，close 后的新段须另起 move。原型不做跨版本迁移。

## Sketch 元数据

```swift
struct SketchMetadata: Codable, Equatable, Sendable {
    var version: Int
    var appVersion: String
    var build: Int
    var compatibilityVersion: Int
    static func decode(_ data: Data) throws -> SketchMetadata
}
```

decode 只接受原始 `meta.json` 数据，最大 1 MiB；四个字段必须分别存在，数值为非负整数，appVersion 非空且最多 256 UTF-8 字节。额外字段忽略。此 API 不解压 ZIP、不导入可编辑图层；UI 必须明确标记“仅元数据检查”。

## 验证命令

```sh
swift test
```

自动测试验证核心状态、树操作、变换、命中、持久化及元数据。macOS 15 是部署目标；测试运行在当前 Apple silicon Mac，不代表已在 macOS 15 系统实机验收。
