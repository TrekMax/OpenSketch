# 原生图层树修复

用户反馈无法拖拽，并要求采用 Sketch 一样的树形列表。用 AppKit NSOutlineView 替换图层区域；页面列表保留。

1. 用稳定 UUID 对象映射文档树，以反向兄弟顺序显示，保留展开状态和选择；原位名称字段复用现有 NativeSidebarRenameField。
2. 使用 NSOutlineView 原生选择、Shift 范围多选、展开、拖动预览与插入标记；固定私有 NSPasteboard 类型承载各行 UUID，校验拖动源列表身份、行集合、当前会话请求、页面与文档快照。
3. 原生 childIndex 落点映射到现有 LayerTreeEditing；支持排序、拖入画板/编组、拖出根层级与一次撤销，取消时清理请求。
4. 保留右键菜单、隐藏/锁定与键盘操作。测试原生落点、粘贴板、选择同步与编辑字段生命周期；构建 Release 后在独立文档实测并记录边界。
