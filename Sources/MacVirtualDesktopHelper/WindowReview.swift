import AppKit

private final class ReviewTable: NSTableView {
 var removeSelection: (() -> Void)?
 override func performKeyEquivalent(with event: NSEvent) -> Bool {
  if event.keyCode == 0,
   event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
   window?.firstResponder === self {
   selectAll(nil)
   return true
  }
  return super.performKeyEquivalent(with: event)
 }
 override func keyDown(with event: NSEvent) {
  if event.keyCode == 51 || event.keyCode == 117 { removeSelection?(); return }
  super.keyDown(with: event)
 }
}

/// Select rows and remove them before confirmation, as in the Windows preview.
final class WindowReview: NSObject, NSTableViewDataSource, NSTableViewDelegate {
 private let alert = NSAlert()
 private var configuredButtons = false
 private let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 360))
 private let scroll = NSScrollView(frame: NSRect(x: 0, y: 40, width: 800, height: 320))
 private var candidates: [DesktopWindow] = []
 private var details: [UInt32: String] = [:]
 private let table = ReviewTable()
 private let remove = NSButton(title: "从列表移除".localized, target: nil, action: nil)
 private let count = NSTextField(labelWithString: "")
 private var confirmButton: NSButton?
 func confirm(title: String, windows: [DesktopWindow], action: String, details: [UInt32: String] = [:]) -> [DesktopWindow]? {
  candidates = windows
  self.details = details
  table.deselectAll(nil)
  for column in table.tableColumns { table.removeTableColumn(column) }
  alert.messageText = title
  alert.informativeText = "检查全部桌面的候选窗口。选中后点击“从列表移除”或按 Delete 排除；确认后仅处理列表中剩余窗口。".localized
  if !configuredButtons {
   confirmButton = alert.addButton(withTitle: action)
   alert.addButton(withTitle: "取消".localized)
   configuredButtons = true
  } else { confirmButton = alert.buttons[0]; confirmButton?.title = action }
  alert.window.isReleasedWhenClosed = false
  scroll.hasVerticalScroller = true
  scroll.borderType = .bezelBorder
  for (id, name, width) in [("app", "应用程序".localized, 180.0), ("title", "窗口".localized, details.isEmpty ? 590.0 : 360.0)] {
   let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
   column.title = name; column.width = width
   table.addTableColumn(column)
  }
  if !details.isEmpty {
   let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
   column.title = "桌面 / 更改".localized; column.width = 230
   table.addTableColumn(column)
  }
  table.dataSource = self; table.delegate = self
  table.allowsMultipleSelection = true
  table.usesAlternatingRowBackgroundColors = true
  table.rowHeight = 26
  table.reloadData()
  table.removeSelection = { [weak self] in self?.removeSelected() }
  if scroll.documentView == nil {
   scroll.documentView = table
   container.addSubview(scroll)
  }
  remove.frame = NSRect(x: 0, y: 2, width: 125, height: 30)
  remove.bezelStyle = .rounded
  remove.target = self; remove.action = #selector(removeSelected)
  if remove.superview == nil { container.addSubview(remove) }
  count.frame = NSRect(x: 140, y: 8, width: 650, height: 20)
  if count.superview == nil { container.addSubview(count) }
  updateControls()
  if alert.accessoryView == nil { alert.accessoryView = container }
  guard alert.runModal() == .alertFirstButtonReturn else { return nil }
  return candidates
 }
 func numberOfRows(in tableView: NSTableView) -> Int { candidates.count }
 func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
  let item = candidates[row]
  let value = tableColumn?.identifier.rawValue == "app" ? item.ownerName : tableColumn?.identifier.rawValue == "detail" ? details[item.id] ?? "" : item.displayTitle
  let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("review")
  let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? NSTableCellView()
  cell.identifier = identifier
  let label: NSTextField
  if let existing = cell.textField { label = existing } else {
   label = NSTextField(labelWithString: "")
   label.translatesAutoresizingMaskIntoConstraints = false
   cell.addSubview(label)
   cell.textField = label
   NSLayoutConstraint.activate([
    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
   ])
  }
  label.stringValue = value
  label.lineBreakMode = .byTruncatingTail
  label.toolTip = value
  return cell
 }
 func tableViewSelectionDidChange(_ notification: Notification) { updateControls() }
 @objc private func removeSelected() {
  for row in table.selectedRowIndexes.reversed() { candidates.remove(at: row) }
  table.deselectAll(nil)
  table.reloadData()
  updateControls()
 }
 private func updateControls() {
  remove.isEnabled = !table.selectedRowIndexes.isEmpty
  confirmButton?.isEnabled = !candidates.isEmpty
  count.stringValue = "本次处理 ".localized + String(candidates.count) + " 个窗口".localized
 }
}
