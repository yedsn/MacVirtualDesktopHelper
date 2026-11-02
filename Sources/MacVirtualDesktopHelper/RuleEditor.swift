import AppKit

final class RuleEditor: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
 private let store: RuleStore
 private let desktopMode: Bool
 private let spaces: () -> [DesktopSpace]
 private var rules: [WindowRule] { desktopMode ? store.state.desktopRules : store.state.cleanupRules }
 private let table = NSTableView()
 private let status = NSTextField(labelWithString: "")
 private let editButton = NSButton(title: "编辑".localized, target: nil, action: nil)
 private let deleteButton = NSButton(title: "删除".localized, target: nil, action: nil)
 private var selectedRuleID: UUID?
 private weak var editingTitleField: NSTextField?
 var changed: (() -> Void)?
 init(store: RuleStore, desktopMode: Bool = false, spaces: @escaping () -> [DesktopSpace] = { [] }) {
  self.store = store
  self.desktopMode = desktopMode
  self.spaces = spaces
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
  window.title = desktopMode ? "管理桌面规则".localized : "管理锁定规则".localized
  window.isReleasedWhenClosed = false
  window.minSize = NSSize(width: 700, height: 340)
  super.init(window: window)
  table.headerView = NSTableHeaderView()
  for (id, title, width) in [("app", "应用身份".localized, 260.0), ("title", "窗口标题".localized, 420.0), ("mode", "匹配".localized, 100.0)] {
   let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
   column.title = title; column.width = width
   table.addTableColumn(column)
  }
  if desktopMode {
   table.tableColumns[0].width = 210
   table.tableColumns[1].width = 300
   table.tableColumns[2].width = 60
   let target = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("target"))
   target.title = "目标桌面".localized; target.width = 240
   table.addTableColumn(target)
  }
  table.dataSource = self; table.delegate = self
  table.target = self; table.doubleAction = #selector(editRule)
  let scroll = NSScrollView()
  scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
  let add = NSButton(title: "新增".localized, target: self, action: #selector(addRule))
  editButton.target = self; editButton.action = #selector(editRule)
  deleteButton.target = self; deleteButton.action = #selector(deleteRule)
  let spacer = NSView()
  spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
  let actions = NSStackView(views: [status, spacer, add, editButton, deleteButton])
  actions.spacing = 8
  guard let content = window.contentView else { return }
  for view in [scroll, actions] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
  NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12), actions.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)])
 }
 required init?(coder: NSCoder) { fatalError() }
 func reloadRules() {
  let selectedID = selectedRuleID
  table.reloadData()
  if let selectedID, let index = rules.firstIndex(where: { $0.id == selectedID }) {
   table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
  } else { table.deselectAll(nil) }
  status.stringValue = String(rules.count) + " 条规则".localized
  updateSelectionActions()
 }
 func tableViewSelectionDidChange(_ notification: Notification) {
  selectedRuleID = rules.indices.contains(table.selectedRow) ? rules[table.selectedRow].id : nil
  updateSelectionActions()
 }
 private func updateSelectionActions() {
  let valid = rules.indices.contains(table.selectedRow)
  editButton.isEnabled = valid; deleteButton.isEnabled = valid
 }
 override func showWindow(_ sender: Any?) { reloadRules(); super.showWindow(sender) }
 func numberOfRows(in tableView: NSTableView) -> Int { rules.count }
 func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
  let rule = rules[row]
  switch tableColumn?.identifier.rawValue {
  case "app": return rule.bundleID.isEmpty ? rule.applicationPath : rule.bundleID
  case "title": return rule.title
  case "target":
   let available = spaces()
   let targets = available.map { DesktopRuleMatcher.Target(uuid: $0.uuid, displayUUID: $0.displayUUID, index: $0.index) }
   guard let index = DesktopRuleMatcher.targetIndex(for: rule, targets: targets) else {
    return "目标缺失或无法唯一定位".localized
   }
   return available[index].title
  default: return rule.titleIsRegex ? "正则".localized : "精确".localized
  }
 }
 @objc private func addRule() { edit(nil) }
 @objc private func editRule() {
  guard rules.indices.contains(table.selectedRow) else { return }
  edit(rules[table.selectedRow])
 }
 @objc private func toggleTitleRegex(_ sender: NSButton) {
  guard let title = editingTitleField else { return }
  if sender.state == .on {
   title.stringValue = NSRegularExpression.escapedPattern(for: title.stringValue)
  } else {
   // Undo literal escapes without stripping regex sequences such as \d or \w.
   let punctuation = #"\.*+?()[]{}^$|/"#
   var literal = ""
   var escaped = false
   for scalar in title.stringValue.unicodeScalars {
    if escaped {
     if !punctuation.unicodeScalars.contains(scalar) { literal += "\\" }
     literal.unicodeScalars.append(scalar)
     escaped = false
    } else if scalar == "\\" {
     escaped = true
    } else {
     literal.unicodeScalars.append(scalar)
    }
   }
   if escaped { literal += "\\" }
   title.stringValue = literal
  }
 }
 private func edit(_ original: WindowRule?) {
  let alert = NSAlert()
  alert.messageText = original == nil ? "新增规则".localized : "编辑规则".localized
  alert.addButton(withTitle: "保存".localized); alert.addButton(withTitle: "取消".localized)
  let bundle = NSTextField(string: original?.bundleID ?? "")
  let path = NSTextField(string: original?.applicationPath ?? "")
  let title = NSTextField(string: original?.title ?? "")
  editingTitleField = title
  defer { editingTitleField = nil }
  let regex = NSButton(checkboxWithTitle: "标题使用正则表达式".localized, target: self, action: #selector(toggleTitleRegex(_:)))
  regex.state = original?.titleIsRegex == true ? .on : .off
  let stack = NSStackView(views: [NSTextField(labelWithString: "Bundle ID（或填写应用路径）".localized), bundle, NSTextField(labelWithString: "应用路径".localized), path, NSTextField(labelWithString: "窗口标题".localized), title, regex])
  let destination = NSPopUpButton()
  let currentSpaces = spaces()
  var missingTarget = false
  if desktopMode {
   destination.addItems(withTitles: currentSpaces.map(\.title))
   if let original {
    let targets = currentSpaces.map { DesktopRuleMatcher.Target(uuid: $0.uuid, displayUUID: $0.displayUUID, index: $0.index) }
    if let index = DesktopRuleMatcher.targetIndex(for: original, targets: targets) { destination.selectItem(at: index) }
    else {
     missingTarget = true
     destination.insertItem(withTitle: "原目标缺失（保留原目标）".localized, at: 0)
     destination.selectItem(at: 0)
    }
   }
   stack.addArrangedSubview(NSTextField(labelWithString: "目标桌面".localized))
   stack.addArrangedSubview(destination)
  }
  stack.orientation = .vertical; stack.alignment = .leading
  stack.frame = NSRect(x: 0, y: 0, width: 560, height: desktopMode ? 290 : 220)
  for field in [bundle, path, title] { field.widthAnchor.constraint(equalToConstant: 560).isActive = true }
  alert.accessoryView = stack
  while true {
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  var rule = original ?? WindowRule(bundleID: "", applicationPath: "", title: "")
  rule.bundleID = bundle.stringValue; rule.applicationPath = path.stringValue
  rule.title = title.stringValue; rule.titleIsRegex = regex.state == .on
  if desktopMode && !(missingTarget && destination.indexOfSelectedItem == 0) {
   let index = destination.indexOfSelectedItem - (missingTarget ? 1 : 0)
   guard currentSpaces.indices.contains(index) else {
    let error = NSAlert()
    error.messageText = "没有可用的目标桌面"
    error.informativeText = "请取消编辑，确认系统中存在普通桌面后重试。"
    error.runModal()
    continue
   }
   let target = currentSpaces[index]
   // Re-read topology after the modal preview: the chosen Space may have
   // disappeared while the editor was open. Never save an accidental fallback.
   guard spaces().contains(where: { $0.uuid == target.uuid && $0.displayUUID == target.displayUUID }) else {
    let error = NSAlert()
    error.messageText = "所选目标桌面已不存在"
    error.informativeText = "本次更改尚未保存。请取消后重新打开编辑器，选择当前可用的桌面。"
    error.runModal()
    continue
   }
   rule.targetSpaceUUID = target.uuid; rule.targetDisplayUUID = target.displayUUID; rule.targetIndex = target.index
  }
  do {
   try store.update { state in
    if desktopMode {
     if let index = state.desktopRules.firstIndex(where: { $0.id == rule.id }) { state.desktopRules[index] = rule }
     else { state.desktopRules.append(rule) }
    } else {
     if let index = state.cleanupRules.firstIndex(where: { $0.id == rule.id }) { state.cleanupRules[index] = rule }
     else { state.cleanupRules.append(rule) }
    }
   }
   selectedRuleID = rule.id
   reloadRules(); changed?(); status.stringValue = "已保存 · ".localized + String(rules.count) + " 条规则".localized
   return
  } catch { NSAlert(error: error).runModal() }
  }
 }
 @objc private func deleteRule() {
  guard rules.indices.contains(table.selectedRow) else { return }
  let id = rules[table.selectedRow].id
  let alert = NSAlert()
  alert.messageText = "删除所选规则？".localized
  alert.addButton(withTitle: "删除".localized); alert.addButton(withTitle: "取消".localized)
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  do {
   try store.update { state in
    if desktopMode { state.desktopRules.removeAll { $0.id == id } }
    else { state.cleanupRules.removeAll { $0.id == id } }
   }
   selectedRuleID = nil
   reloadRules(); changed?()
  } catch { NSAlert(error: error).runModal() }
 }
}
