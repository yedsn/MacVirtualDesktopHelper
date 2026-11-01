import AppKit

final class SnapshotController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
 private let store: RuleStore
 private let table = NSTableView()
 private var selectedID: UUID?
 private var selectionActions: [NSButton] = []
 var changed: (() -> Void)?
 var scheduleChanged: (() -> Void)?
 init(store: RuleStore) {
  self.store = store
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
  window.title = "规则快照".localized; window.isReleasedWhenClosed = false
  window.minSize = NSSize(width: 850, height: 360)
  super.init(window: window)
  for (id, title, width) in [("name", "名称".localized, 300.0), ("date", "时间".localized, 220.0), ("kind", "类型".localized, 80.0), ("counts", "锁定 / 桌面规则".localized, 170.0)] {
   let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; table.addTableColumn(column)
  }
  table.dataSource = self; table.delegate = self
  table.target = self; table.doubleAction = #selector(viewSnapshot)
  table.usesAlternatingRowBackgroundColors = true
  let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
  let capture = NSButton(title: "手动快照".localized, target: self, action: #selector(captureSnapshot))
  let view = NSButton(title: "查看".localized, target: self, action: #selector(viewSnapshot))
  let rename = NSButton(title: "重命名".localized, target: self, action: #selector(renameSnapshot))
  let restore = NSButton(title: "恢复".localized, target: self, action: #selector(restoreSnapshot))
  let remove = NSButton(title: "删除".localized, target: self, action: #selector(deleteSnapshot))
  selectionActions = [view, rename, restore, remove]
  selectionActions.forEach { $0.isEnabled = false }
  let schedule = NSButton(title: "自动快照设置".localized, target: self, action: #selector(editSchedule))
  let export = NSButton(title: "导出配置".localized, target: self, action: #selector(exportBackup))
  let importButton = NSButton(title: "导入配置".localized, target: self, action: #selector(importBackup))
  let actions = NSStackView(views: [capture, view, rename, restore, remove, schedule, export, importButton]); actions.spacing = 8
  guard let content = window.contentView else { return }
  for item in [scroll, actions] { item.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(item) }
  NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12), actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), actions.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 12), actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)])
 }
 required init?(coder: NSCoder) { fatalError() }
 func reload() {
  let id = selectedID
  table.reloadData()
  if let id, let index = store.state.snapshots.firstIndex(where: { $0.id == id }) {
   table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
  } else { table.deselectAll(nil) }
  selectedID = selected?.id
  selectionActions.forEach { $0.isEnabled = selectedID != nil }
 }
 func tableViewSelectionDidChange(_ notification: Notification) {
  selectedID = selected?.id
  selectionActions.forEach { $0.isEnabled = selectedID != nil }
 }
 override func showWindow(_ sender: Any?) { reload(); super.showWindow(sender) }
 @objc private func editSchedule() {
  let settings = store.state.snapshotSettings ?? SnapshotSettings()
  let enabled = NSButton(checkboxWithTitle: "启用自动快照".localized, target: nil, action: nil)
  enabled.state = settings.enabled ? .on : .off
  let interval = NSTextField(string: String(settings.intervalMinutes))
  let maximum = NSTextField(string: String(settings.maximumCount))
  let stack = NSStackView(views: [enabled, NSTextField(labelWithString: "间隔（分钟，1～10080）".localized), interval, NSTextField(labelWithString: "保留自动快照数量（1～1000）".localized), maximum])
  stack.orientation = .vertical; stack.alignment = .leading
  stack.frame = NSRect(x: 0, y: 0, width: 360, height: 170)
  let alert = NSAlert(); alert.messageText = "自动快照设置".localized
  alert.informativeText = "保存后等待完整间隔，关闭管理窗口后仍继续；手动快照不参与轮转。".localized
  alert.accessoryView = stack
  alert.addButton(withTitle: "保存".localized); alert.addButton(withTitle: "取消".localized)
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  guard let minutes = Int(interval.stringValue), let count = Int(maximum.stringValue) else {
   NSAlert(error: NSError(domain: "SnapshotSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "请输入整数。".localized])).runModal(); return
  }
  do {
   try store.update { $0.snapshotSettings = SnapshotSettings(enabled: enabled.state == .on, intervalMinutes: minutes, maximumCount: count) }
   scheduleChanged?()
  } catch { NSAlert(error: error).runModal() }
 }
 @objc func exportBackup() {
  let panel = NSSavePanel(); panel.nameFieldStringValue = "MacVirtualDesktopHelper-backup.json"
  guard panel.runModal() == .OK, let url = panel.url else { return }
  perform { try ConfigurationBackupService.export(store: store, to: url) }
 }
 @objc func importBackup() {
  let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do {
   let backup = try ConfigurationBackupService.preview(from: url)
   let alert = NSAlert(); alert.messageText = "导入配置？".localized
   alert.informativeText = "将替换应用设置、锁定规则 ".localized + String(backup.state.cleanupRules.count) + " 条、桌面规则 ".localized + String(backup.state.desktopRules.count) + " 条和快照 ".localized + String(backup.state.snapshots.count) + " 份及自动快照设置。不会移动窗口或创建桌面；系统权限与登录项授权不随配置导入。".localized
   alert.addButton(withTitle: "导入".localized); alert.addButton(withTitle: "取消".localized)
   guard alert.runModal() == .alertFirstButtonReturn else { return }
   try ConfigurationBackupService.restore(backup, store: store)
   reload(); scheduleChanged?(); changed?()
  } catch { NSAlert(error: error).runModal() }
 }
 func numberOfRows(in tableView: NSTableView) -> Int { store.state.snapshots.count }
 func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
  let item = store.state.snapshots[row]
  switch tableColumn?.identifier.rawValue {
  case "name": return item.name
  case "date": return DateFormatter.localizedString(from: item.createdAt, dateStyle: .short, timeStyle: .medium)
  case "kind": return item.automatic ? "自动".localized : "手动".localized
  default: return String(item.cleanupRules.count) + " / " + String(item.desktopRules.count)
  }
 }
 private var selected: RuleSnapshot? { store.state.snapshots.indices.contains(table.selectedRow) ? store.state.snapshots[table.selectedRow] : nil }
 private func ask(_ title: String, value: String) -> String? {
  let alert = NSAlert(); alert.messageText = title
  let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 400, height: 26); alert.accessoryView = field
  alert.addButton(withTitle: "保存".localized); alert.addButton(withTitle: "取消".localized)
  return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
 }
 private func perform(_ action: () throws -> Void) {
  do { try action(); reload(); changed?() } catch { NSAlert(error: error).runModal() }
 }
 @objc private func captureSnapshot() {
  guard let name = ask("手动规则快照".localized, value: "快照 ".localized + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)) else { return }
  perform { try store.capture(name: name) }
 }
 @objc private func viewSnapshot() {
  guard let item = selected else { return }
  let alert = NSAlert(); alert.messageText = item.name
  alert.informativeText = "锁定规则 ".localized + String(item.cleanupRules.count) + " 条；桌面规则 ".localized + String(item.desktopRules.count) + " 条。".localized + (item.includesCleanupRules ? "" : "此旧快照不含锁定规则。".localized)
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 350))
  scroll.hasVerticalScroller = true
  scroll.borderType = .bezelBorder
  let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 350))
  text.isEditable = false; text.isRichText = false
  text.isVerticallyResizable = true
  text.autoresizingMask = [.width]
  text.textContainer?.widthTracksTextView = true
  text.font = .systemFont(ofSize: 12)
  text.string = (item.cleanupRules.map { "锁定：".localized + ($0.bundleID.isEmpty ? $0.applicationPath : $0.bundleID) + " — " + $0.title + ($0.titleIsRegex ? " [正则]".localized : " [精确]".localized) } + item.desktopRules.map { "桌面 ".localized + String(($0.targetIndex ?? -1) + 1) + "：" + ($0.bundleID.isEmpty ? $0.applicationPath : $0.bundleID) + " — " + $0.title + ($0.titleIsRegex ? " [正则]".localized : " [精确]".localized) }).joined(separator: "\n\n")
  scroll.documentView = text
  alert.accessoryView = scroll
  alert.runModal()
 }
 @objc private func renameSnapshot() {
  guard let item = selected, let name = ask("重命名快照".localized, value: item.name), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
  perform { try store.update { state in if let index = state.snapshots.firstIndex(where: { $0.id == item.id }) { state.snapshots[index].name = name } } }
 }
 @objc private func restoreSnapshot() {
  guard let item = selected else { return }
  let alert = NSAlert(); alert.messageText = "恢复规则快照？".localized
  alert.informativeText = (item.includesCleanupRules ? "将替换当前锁定规则和桌面规则。".localized : "此旧快照不含锁定规则，将保留当前锁定规则，仅替换桌面规则。".localized) + "不会移动窗口；需要时另行应用桌面规则。".localized
  alert.addButton(withTitle: "恢复".localized); alert.addButton(withTitle: "取消".localized)
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  perform { try store.restore(id: item.id) }
 }
 @objc private func deleteSnapshot() {
  guard let item = selected else { return }
  let alert = NSAlert(); alert.messageText = "删除快照“".localized + item.name + "”？"
  alert.addButton(withTitle: "删除".localized); alert.addButton(withTitle: "取消".localized)
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  perform { try store.update { $0.snapshots.removeAll { $0.id == item.id } } }
 }
}
