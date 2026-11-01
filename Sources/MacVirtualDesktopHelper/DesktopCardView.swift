import AppKit

final class WindowListTable: NSTableView {
 var navigate: ((UInt16) -> Bool)?
 var activateWindow: (() -> Void)?
 var toggleLock: (() -> Void)?
 override func performKeyEquivalent(with event: NSEvent) -> Bool {
  let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
  if event.keyCode == 37, modifiers == .command, window?.firstResponder === self {
   toggleLock?()
   return true
  }
  return super.performKeyEquivalent(with: event)
 }
 override func keyDown(with event: NSEvent) {
  if event.keyCode == 53 { window?.performClose(nil); return }
  if event.keyCode == 36 { activateWindow?(); return }
  if event.keyCode == 37 && event.modifierFlags.contains(.command) { toggleLock?(); return }
  if navigate?(event.keyCode) == true { return }
  super.keyDown(with: event)
 }
}

final class DesktopCardView: NSView, NSTableViewDataSource, NSTableViewDelegate {
 let group: WindowGroup
 let table = WindowListTable()
 let heading = NSTextField(labelWithString: "")
 let scroll = NSScrollView()
 var onSelect: ((DesktopWindow) -> Void)?
 var onActivate: (() -> Void)?
 var onDrop: ((UInt32, UInt64) -> Void)?
 var isLocked: ((DesktopWindow) -> Bool)?
 var onToggleLock: ((DesktopWindow) -> Void)?
 private let fontSize: CGFloat
 private let solidBackground: Bool
 private let headerBackground = NSView()
 private let headerSeparator = NSView()
 init(group: WindowGroup, fontSize: CGFloat = 14, solidBackground: Bool = false) {
  self.fontSize = fontSize
  self.solidBackground = solidBackground
  self.group = group
  super.init(frame: .zero)
  registerForDraggedTypes([NSPasteboard.PasteboardType("local.macvirtualdesktophelper.window")])
  wantsLayer = true
  layer?.borderWidth = 1
  layer?.cornerRadius = 6
  layer?.masksToBounds = true
  headerBackground.wantsLayer = true
  headerSeparator.wantsLayer = true
  addSubview(headerBackground)
  addSubview(headerSeparator)
  updateColors()
  heading.stringValue = group.space.title + " (" + String(group.windows.count) + ")" + (group.space.isCurrent ? " · 当前".localized : "")
  heading.font = .systemFont(ofSize: fontSize, weight: .semibold)
  addSubview(heading)
  table.headerView = nil
  table.rowHeight = max(28, fontSize + 13)
  table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window")))
  table.dataSource = self; table.delegate = self
  table.registerForDraggedTypes([NSPasteboard.PasteboardType("local.macvirtualdesktophelper.window")])
  table.setDraggingSourceOperationMask(.move, forLocal: true)
  table.target = self; table.doubleAction = #selector(activate)
  table.activateWindow = { [weak self] in self?.onActivate?() }
  table.toggleLock = { [weak self] in
   guard let self, self.table.selectedRow >= 0 else { return }
   self.onToggleLock?(self.group.windows[self.table.selectedRow])
  }
  scroll.documentView = table
  scroll.hasVerticalScroller = true
  scroll.autohidesScrollers = true
  addSubview(scroll)
 }
 required init?(coder: NSCoder) { fatalError() }
 private func updateColors() {
  effectiveAppearance.performAsCurrentDrawingAppearance {
   layer?.borderColor = NSColor.separatorColor.cgColor
   layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
   headerBackground.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(solidBackground ? 0.065 : 0.035).cgColor
   headerSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
  }
 }
 override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
 override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
  guard group.space.id != 0 else { return [] }
  return sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("local.macvirtualdesktophelper.window")) == nil ? [] : .move
 }
 override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
  guard group.space.id != 0 else { return false }
  guard let text = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("local.macvirtualdesktophelper.window")), let id = UInt32(text) else { return false }
  onDrop?(id, group.space.id)
  return true
 }
 override func layout() {
  super.layout()
  let headerHeight = max(32, fontSize + 16)
  headerBackground.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
  headerSeparator.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: 1)
  heading.frame = NSRect(x: 9, y: bounds.height - headerHeight + 5, width: bounds.width - 18, height: headerHeight - 10)
  scroll.frame = NSRect(x: 1, y: 1, width: bounds.width - 2, height: bounds.height - headerHeight)
  table.tableColumns.first?.width = bounds.width - 4
 }
 func numberOfRows(in tableView: NSTableView) -> Int { group.windows.count }
 func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
  let item = group.windows[row]
  let cell = NSTableCellView()
  let lock = NSButton(frame: NSRect(x: 2, y: 3, width: 23, height: 22))
  lock.image = NSImage(systemSymbolName: isLocked?(item) == true ? "lock.fill" : "lock.open", accessibilityDescription: "切换清理保护".localized)
  lock.isBordered = false
  lock.tag = row
  lock.target = self; lock.action = #selector(toggleLock(_:))
  cell.addSubview(lock)
  let icon = NSImageView(frame: NSRect(x: 27, y: 5, width: 18, height: 18))
  icon.image = item.icon
  let label = NSTextField(labelWithString: item.displayTitle + " — " + item.ownerName)
  label.frame = NSRect(x: 52, y: 4, width: max(20, table.bounds.width - 58), height: fontSize + 6)
  label.autoresizingMask = [.width]
  label.font = .systemFont(ofSize: fontSize)
  let locked = isLocked?(item) == true
  let protectedColor = NSColor(srgbRed: 35.0 / 255, green: 112.0 / 255, blue: 55.0 / 255, alpha: 1)
  label.textColor = locked ? protectedColor : item.isSticky ? NSColor(srgbRed: 105.0 / 255, green: 105.0 / 255, blue: 105.0 / 255, alpha: 1) : .labelColor
  lock.contentTintColor = locked ? protectedColor : .gray
  label.lineBreakMode = .byTruncatingTail
  cell.addSubview(icon); cell.addSubview(label)
  cell.toolTip = label.stringValue
  return cell
 }
 func tableViewSelectionDidChange(_ notification: Notification) {
  if table.selectedRow >= 0 { onSelect?(group.windows[table.selectedRow]) }
 }
 func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
  let window = group.windows[row]
  guard !window.isSticky, window.hasKnownSpace else { return nil }
  let item = NSPasteboardItem()
  item.setString(String(window.id), forType: NSPasteboard.PasteboardType("local.macvirtualdesktophelper.window"))
  return item
 }
 func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
  guard group.space.id != 0 else { return [] }
  tableView.setDropRow(-1, dropOperation: .on)
  return .move
 }
 func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
  guard group.space.id != 0 else { return false }
  guard let text = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("local.macvirtualdesktophelper.window")), let id = UInt32(text) else { return false }
  onDrop?(id, group.space.id)
  return true
 }
 @objc private func activate() { onActivate?() }
 @objc private func toggleLock(_ sender: NSButton) { onToggleLock?(group.windows[sender.tag]) }
}
