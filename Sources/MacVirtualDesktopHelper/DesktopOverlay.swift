import AppKit

final class DesktopOverlay {
 private var switchPanels: [NSPanel] = []
 private var statusPanels: [NSPanel] = []
 private var hideWork: DispatchWorkItem?
 private var currentSpaces: [String: UInt64] = [:]
 func update(spaces: [DesktopSpace], settings: OverlaySettings) {
  let active = spaces.filter { $0.isCurrent }
  let switched = active.contains { space in currentSpaces[space.displayUUID].map { $0 != space.id } ?? false }
  currentSpaces = Dictionary(active.map { ($0.displayUUID, $0.id) }, uniquingKeysWith: { first, _ in first })
  if !settings.showSwitch {
   hideWork?.cancel()
   switchPanels.forEach { $0.orderOut(nil) }; switchPanels.removeAll()
  }
  statusPanels.forEach { $0.orderOut(nil) }; statusPanels.removeAll()
  let screens = settings.allDisplays ? NSScreen.screens : (NSScreen.main.map { [$0] } ?? [])
  if settings.showStatus {
   var status = settings
   status.position = settings.statusPosition ?? "topcenter"
   status.translucent = settings.statusTranslucent ?? settings.translucent
   status.animate = settings.statusAnimate ?? settings.animate
   let statusScreens = (settings.statusAllDisplays ?? settings.allDisplays) ? NSScreen.screens : (NSScreen.main.map { [$0] } ?? [])
   statusPanels = statusScreens.compactMap { screen in
    guard let title = title(for: screen, spaces: active) else { return nil }
    return panel(title: title, screen: screen, compact: true, settings: status)
   }
   statusPanels.forEach { panel in
    panel.alphaValue = status.animate ? 0 : 1
    panel.orderFrontRegardless()
    if status.animate { NSAnimationContext.runAnimationGroup { context in context.duration = 0.15; panel.animator().alphaValue = 1 } }
   }
  }
  guard switched else { return }
  hideWork?.cancel()
  switchPanels.forEach { $0.orderOut(nil) }; switchPanels.removeAll()
  guard settings.showSwitch else { return }
  switchPanels = screens.compactMap { screen in
   guard let title = title(for: screen, spaces: active) else { return nil }
   return panel(title: title, screen: screen, compact: false, settings: settings)
  }
  switchPanels.forEach { panel in
   panel.alphaValue = settings.animate ? 0 : 1
   panel.orderFrontRegardless()
   if settings.animate { NSAnimationContext.runAnimationGroup { context in context.duration = 0.15; panel.animator().alphaValue = 1 } }
  }
  guard settings.duration > 0 else { return }
  let work = DispatchWorkItem { [weak self] in self?.switchPanels.forEach { $0.orderOut(nil) }; self?.switchPanels.removeAll() }
  hideWork = work
  DispatchQueue.main.asyncAfter(deadline: .now() + settings.duration, execute: work)
 }
 private func title(for screen: NSScreen, spaces: [DesktopSpace]) -> String? {
  guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
   let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
  let displayID = CFUUIDCreateString(nil, uuid) as String
  return Self.title(displayUUID: displayID, spaces: spaces)
 }
 static func title(displayUUID: String, spaces: [DesktopSpace]) -> String? {
  if let space = spaces.first(where: { $0.displayUUID.caseInsensitiveCompare(displayUUID) == .orderedSame }) { return space.title }
  // With separate Spaces disabled, SkyLight exposes one shared desktop for all screens.
  return spaces.count == 1 ? spaces.first?.title : nil
 }
 private func panel(title: String, screen: NSScreen, compact: Bool, settings: OverlaySettings) -> NSPanel {
  let size = compact ? NSSize(width: 250, height: 40) : NSSize(width: 480, height: 180)
  let visible = screen.visibleFrame
  let y: CGFloat
  if settings.position.hasPrefix("top") { y = visible.maxY - size.height - 16 }
  else if settings.position.hasPrefix("bottom") { y = visible.minY + 24 }
  else { y = visible.midY - size.height / 2 }
  let x: CGFloat
  if settings.position.hasSuffix("left") { x = visible.minX + 16 }
  else if settings.position.hasSuffix("right") { x = visible.maxX - size.width - 16 }
  else { x = visible.midX - size.width / 2 }
  let panel = NSPanel(contentRect: NSRect(x: x, y: y, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.level = .floating
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
  panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
  panel.isOpaque = false; panel.backgroundColor = .clear
  let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
  background.material = .hudWindow; background.state = .active
  background.blendingMode = .behindWindow
  background.wantsLayer = true; background.layer?.cornerRadius = 12; background.layer?.masksToBounds = true
  if !settings.translucent { background.material = .windowBackground; background.blendingMode = .withinWindow }
  let label = NSTextField(labelWithString: title)
  label.font = .systemFont(ofSize: compact ? 13 : 30, weight: .medium)
  label.alignment = .center
  label.frame = NSRect(x: 12, y: (size.height - (compact ? 20 : 44)) / 2, width: size.width - 24, height: compact ? 20 : 44)
  background.addSubview(label); panel.contentView = background
  return panel
 }
 deinit { hideWork?.cancel(); (switchPanels + statusPanels).forEach { $0.orderOut(nil) } }
}
