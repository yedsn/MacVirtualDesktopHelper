import AppKit

/// Coordinates the first usable window-switcher slice. Input registration is
/// deliberately kept in GlobalHotKeys; this controller owns candidate scope,
/// selection state and activation validation.
final class WindowSwitcherController {
 private let skyLight: SkyLightService
 private let catalog: WindowCatalog
 private let accessibility: AccessibilityWindowService
 private var session: WindowSwitcherSession?
 private var windowIdentities: [UInt32: AXUIElement] = [:]
 private var history: [UInt32] = []
 private var flagsMonitor: Any?
 private var keyMonitor: Any?
 private var panel: NSPanel?
 private var localMonitor: Any?
 private var sessionSpaceID: UInt64?
 private var targetScreen: NSScreen?
 var holdFlags: NSEvent.ModifierFlags = .option
 var enabled = false {
  didSet { if !enabled { cancel(); history.removeAll() } }
 }
 private let collectionQueue = DispatchQueue(label: "window-switcher.collection", qos: .userInitiated)
 private var generation = UUID()
 private var preparing = false
 private var pendingDirections: [Bool] = []
 private var released = false
 private var interruptionObservers: [NSObjectProtocol] = []
 private var historyTimer: Timer?

 init(skyLight: SkyLightService, catalog: WindowCatalog, accessibility: AccessibilityWindowService) {
  self.skyLight = skyLight; self.catalog = catalog; self.accessibility = accessibility
  let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
   guard self?.enabled == true else { return }
   if let self, self.session != nil || self.preparing {
    guard self.accessibility.isTrusted, CGPreflightListenEventAccess() else { self.cancel(); return }
    if NSEvent.modifierFlags.intersection(self.holdFlags).isEmpty {
     if self.preparing { self.released = true } else { self.commit() }
    }
    return
   }
   guard let self, !self.preparing, self.session == nil, self.accessibility.isTrusted,
    let app = NSWorkspace.shared.frontmostApplication,
    app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
    let id = self.accessibility.focusedWindowID(pid: app.processIdentifier) else { return }
   self.history.removeAll { $0 == id }; self.history.insert(id, at: 0)
   if self.history.count > 256 { self.history.removeLast(self.history.count - 256) }
  }
  RunLoop.main.add(timer, forMode: .common); historyTimer = timer
  for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
   interruptionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
  }
  interruptionObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
  flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
   guard let self else { return }
   if event.modifierFlags.intersection(self.holdFlags).isEmpty {
    if self.preparing { self.released = true } else { self.commit() }
   }
  }
  keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
   guard let self, self.preparing || self.session?.state == .selecting else { return }
   if event.keyCode == 53 { self.cancel() }
  }
  localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
   guard let self, self.preparing || self.session?.state == .selecting else { return event }
   if event.type == .keyDown, event.keyCode == 53 { self.cancel(); return nil }
   if event.type == .flagsChanged, event.modifierFlags.intersection(self.holdFlags).isEmpty {
    if self.preparing { self.released = true } else { self.commit() }
    return event
   }
   return event.keyCode == 48 ? nil : event
  }
 }

 func trigger(reverse: Bool = false) {
  guard enabled else { return }
  if let active = session, active.state == .selecting {
   active.advance(reverse: reverse)
   updatePanel()
   return
  }
  if preparing { pendingDirections.append(reverse); return }
  guard accessibility.isTrusted else { accessibility.requestAccess(); reportFailure("需要辅助功能权限才能切换窗口。", settingsAnchor: "Privacy_Accessibility"); return }
  guard flagsMonitor != nil, keyMonitor != nil else {
   reportFailure("键盘监听未能创建，请检查辅助功能和输入监听权限后重新启动应用。", settingsAnchor: "Privacy_ListenEvent")
   return
  }
  guard CGPreflightListenEventAccess() else {
   CGRequestListenEventAccess()
   reportFailure("需要输入监听权限，请在系统设置中授权后重试。", settingsAnchor: "Privacy_ListenEvent")
   return
  }
  let currentID = accessibility.focusedWindowID(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
  let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
  var screen: NSScreen?
  if let currentID, let record = raw.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == currentID }),
   let bounds = record[kCGWindowBounds as String] as? [String: Any],
   let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), let primary = NSScreen.screens.first {
   let center = NSPoint(x: rect.midX, y: primary.frame.maxY - rect.midY)
   screen = NSScreen.screens.first { $0.frame.contains(center) }
  }
  if screen == nil { screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } }
  guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
   let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { reportFailure("无法确定窗口所在屏幕。"); return }
  let displayID = CFUUIDCreateString(nil, uuid) as String
  guard let actual = skyLight.currentSpace(displayUUID: displayID) else { reportFailure("无法确定当前桌面。"); return }
  guard actual.isRegular else { reportFailure("暂不支持原生全屏空间的窗口切换。"); return }
  let spaces = skyLight.spaces()
  guard let current = spaces.first(where: { $0.id == actual.id && $0.isCurrent }) else { reportFailure("当前空间不支持窗口切换。"); return }
  targetScreen = screen
  sessionSpaceID = current.id
  preparing = true; released = false; pendingDirections = []; generation = UUID()
  let token = generation
  collectionQueue.async { [weak self] in
   guard let self else { return }
   let snapshot = self.catalog.snapshot(targetSpaceID: current.id)
   let selectable = (snapshot.groups.first(where: { $0.space.id == current.id })?.windows ?? [])
    .filter { !$0.isExcludedFromSwitcher && !$0.isAccessibilityUnavailable }
   let identities = snapshot.switcherIdentities
   DispatchQueue.main.async { [weak self] in
    guard let self, self.generation == token, self.preparing else { return }
    self.preparing = false
    self.windowIdentities = identities
    guard selectable.contains(where: { !$0.isAccessibilityUnavailable }) else { self.cancel(); self.reportFailure("当前桌面没有可切换的窗口。"); return }
    self.session = WindowSwitcherSession(candidates: selectable, currentID: currentID, mostRecentIDs: self.history, reverse: reverse)
    for direction in self.pendingDirections { self.session?.advance(reverse: direction) }
    self.pendingDirections = []
    if self.released || NSEvent.modifierFlags.intersection(self.holdFlags).isEmpty { self.commit() }
    else { self.showPanel() }
   }
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
   guard let self, self.generation == token, self.preparing else { return }
   self.cancel(); self.reportFailure("窗口读取超时，请重试。")
  }
 }

 private func showPanel() {
  let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 92), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hidesOnDeactivate = false
  panel.acceptsMouseMovedEvents = true
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  self.panel = panel; updatePanel()
  let screen = targetScreen
  if let screen { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 260, y: screen.visibleFrame.midY - panel.frame.height / 2)) }
  panel.orderFrontRegardless()
 }

 private func updatePanel() {
  guard let panel, let session else { return }
  let screen = targetScreen
  let height = min(CGFloat(session.candidates.count * 64 + 24), min(540, (screen?.visibleFrame.height ?? 700) - 80))
  panel.setContentSize(NSSize(width: 520, height: max(88, height)))
  let host = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 520, height: max(88, height)))
  host.material = .hudWindow; host.state = .active; host.wantsLayer = true; host.layer?.cornerRadius = 12
  let scroll = NSScrollView(frame: host.bounds.insetBy(dx: 12, dy: 12))
  scroll.hasVerticalScroller = true; scroll.drawsBackground = false
  let document = SwitcherListView(frame: NSRect(x: 0, y: 0, width: 480, height: CGFloat(session.candidates.count * 64)))
  for (index, item) in session.candidates.enumerated() {
   let status = item.backgroundStateDescription
   let description = item.displayTitle + (status.isEmpty ? "" : " · " + status)
   let row = SwitcherRowView(frame: NSRect(x: 0, y: CGFloat(index * 64), width: 480, height: 60))
   row.hover = { [weak self, weak session, weak document] in
    guard let self, let session, self.session === session, session.select(windowID: item.id), let document else { return }
    for (rowIndex, view) in document.subviews.enumerated() {
     let selected = rowIndex == session.selectedIndex
     view.setAccessibilitySelected(selected)
     view.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : nil
    }
   }
   row.activate = { [weak self, weak session] in
    guard let self, let session, self.session === session, session.select(windowID: item.id) else { return }
    self.commit()
   }
   row.wantsLayer = true; row.layer?.cornerRadius = 8
   row.setAccessibilityElement(true)
   row.setAccessibilityRole(.row)
   row.setAccessibilityLabel(item.ownerName + " · " + description)
   row.setAccessibilitySelected(index == session.selectedIndex)
   if index == session.selectedIndex { row.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor }
   let icon = NSImageView(frame: NSRect(x: 10, y: 14, width: 32, height: 32)); icon.image = item.icon
   row.addSubview(icon)
   let name = NSTextField(labelWithString: item.ownerName)
   name.font = .systemFont(ofSize: 13, weight: .semibold); name.frame = NSRect(x: 54, y: 32, width: 410, height: 18)
   row.addSubview(name)
   let detail = NSTextField(labelWithString: description)
   detail.lineBreakMode = .byTruncatingTail; detail.textColor = .secondaryLabelColor
   detail.frame = NSRect(x: 54, y: 10, width: 410, height: 18); row.addSubview(detail)
   document.addSubview(row)
  }
  scroll.documentView = document; host.addSubview(scroll); panel.contentView = host
  if let selected = session.selectedIndex {
   document.scrollToVisible(NSRect(x: 0, y: CGFloat(selected * 64), width: 480, height: 64))
  }
 }

 private func commit() {
  guard let session, let target = session.commit() else { return }
  guard let identity = windowIdentities[target.id],
        let liveIdentity = accessibility.windowIdentity(target), CFEqual(identity, liveIdentity),
        let originSpaceID = sessionSpaceID,
        skyLight.spaces().contains(where: { $0.id == originSpaceID && $0.isCurrent }),
        skyLight.spaceIDs(for: target.id).contains(originSpaceID),
        NSRunningApplication(processIdentifier: target.pid).map({ ($0.bundleIdentifier ?? "") == target.bundleID }) == true,
        accessibility.containsWindow(target) else { cancel(); reportFailure("目标窗口已关闭、移走或无法操作。"); return }
  panel?.orderOut(nil); panel = nil
  self.session = nil
  windowIdentities.removeAll()
  if let error = accessibility.focus(target, activateAllWindows: false, expectedWindow: identity) {
   reportFailure(error)
  } else {
   verifyFocus(target, originSpaceID: originSpaceID, token: generation, attempts: 8)
  }
 }
 private func verifyFocus(_ target: DesktopWindow, originSpaceID: UInt64, token: UUID, attempts: Int) {
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
   guard let self, self.generation == token else { return }
   let sameSpace = self.skyLight.spaces().contains { $0.id == originSpaceID && $0.isCurrent }
   let focused = self.accessibility.focusedWindowID(pid: target.pid) == target.id
   let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
   let visibleApplication = NSRunningApplication(processIdentifier: target.pid)?.isHidden == false
   if sameSpace && focused && frontmost && visibleApplication && self.accessibility.isMinimized(target) == false {
    self.history.removeAll { $0 == target.id }; self.history.insert(target.id, at: 0)
   } else if sameSpace && attempts > 1 {
    self.verifyFocus(target, originSpaceID: originSpaceID, token: token, attempts: attempts - 1)
   } else { self.reportFailure("窗口未能在原桌面取得焦点。") }
  }
 }
 private func reportFailure(_ message: String, settingsAnchor: String? = nil) {
  ApplicationLog.write("Window switcher: " + message)
  NSSound.beep()
  let alert = NSAlert()
  alert.messageText = "窗口切换未完成"
  alert.informativeText = message
  alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  alert.window.level = .floating
  alert.addButton(withTitle: "好")
  if settingsAnchor != nil { alert.addButton(withTitle: "打开权限设置") }
  NSApp.activate(ignoringOtherApps: true)
  alert.window.orderFrontRegardless()
  if alert.runModal() == .alertSecondButtonReturn, let anchor = settingsAnchor {
   if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) { NSWorkspace.shared.open(url) }
  }
 }
 func cancel() { generation = UUID(); preparing = false; pendingDirections = []; released = false; session?.cancel(); session = nil; windowIdentities.removeAll(); panel?.orderOut(nil); panel = nil }
 func cancelIfSpaceChanged() {
  guard let sessionSpaceID, skyLight.spaces().first(where: { $0.id == sessionSpaceID })?.isCurrent != true else { return }
  cancel()
 }
 deinit {
  historyTimer?.invalidate()
  for observer in interruptionObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer); NotificationCenter.default.removeObserver(observer) }
  if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }; if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }; panel?.orderOut(nil)
 }
}

private final class SwitcherListView: NSView {
 override var isFlipped: Bool { true }
}

private final class SwitcherRowView: NSView {
 var activate: (() -> Void)?
 var hover: (() -> Void)?
 private var hoverTracking: NSTrackingArea?
 override func updateTrackingAreas() {
  super.updateTrackingAreas()
  if let hoverTracking { removeTrackingArea(hoverTracking) }
  let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
  addTrackingArea(area)
  hoverTracking = area
 }
 override func mouseMoved(with event: NSEvent) { hover?() }
 override func mouseEntered(with event: NSEvent) { hover?() }
 override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
 override func hitTest(_ point: NSPoint) -> NSView? {
  super.hitTest(point) == nil ? nil : self
 }
 override func mouseUp(with event: NSEvent) {
  if bounds.contains(convert(event.locationInWindow, from: nil)) { activate?() }
 }
 override func accessibilityPerformPress() -> Bool {
  guard let activate else { return false }
  activate()
  return true
 }
}
