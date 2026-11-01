import AppKit

final class DesktopOverlay {
 private var startupPanels: [NSPanel] = []
 private var startupHideWork: DispatchWorkItem?
 private var switchPanels: [NSPanel] = []
 private var statusPanels: [NSPanel] = []
 private var hideWork: DispatchWorkItem?
 private var currentSpaces: [String: UInt64] = [:]
 func showStartup(settings: ApplicationSettings) {
  let overlay = settings.overlay ?? OverlaySettings()
  guard settings.showStartupOverlay ?? true, overlay.showSwitch else { return }
  startupHideWork?.cancel()
  startupPanels.forEach { $0.orderOut(nil) }
  let screens = overlay.allDisplays ? NSScreen.screens : (NSScreen.main.map { [$0] } ?? [])
  startupPanels = screens.map { panel(title: settings.startupOverlayText ?? "MacVirtualDesktopHelper", screen: $0, compact: false, settings: overlay) }
  startupPanels.forEach { $0.orderFrontRegardless() }
  let work = DispatchWorkItem { [weak self] in
   self?.startupPanels.forEach { $0.orderOut(nil) }
   self?.startupPanels.removeAll()
  }
  startupHideWork = work
  DispatchQueue.main.asyncAfter(deadline: .now() + (settings.startupOverlayDuration ?? 2), execute: work)
 }
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
  let requestedSize = compact ? NSSize(width: settings.statusWidth ?? 250, height: settings.statusHeight ?? 40) : NSSize(width: settings.switchWidth ?? 480, height: settings.switchHeight ?? 180)
  let size = NSSize(width: min(requestedSize.width, screen.visibleFrame.width), height: min(requestedSize.height, screen.visibleFrame.height))
  let visible = screen.visibleFrame
  let y: CGFloat
  if settings.position.hasPrefix("top") { y = visible.maxY - size.height - 16 }
  else if settings.position.hasPrefix("bottom") { y = visible.minY + 24 }
  else { y = visible.midY - size.height / 2 }
  let x: CGFloat
  if settings.position.hasSuffix("left") { x = visible.minX + 16 }
  else if settings.position.hasSuffix("right") { x = visible.maxX - size.width - 16 }
  else { x = visible.midX - size.width / 2 }
  let panel = NSPanel(contentRect: NSRect(x: x, y: min(max(y + (compact ? (settings.statusOffset ?? 0) : 0), visible.minY), visible.maxY - size.height), width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.level = .floating
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
  panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
  panel.isOpaque = false; panel.backgroundColor = .clear
  let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
  background.material = .hudWindow; background.state = .active
  background.blendingMode = .behindWindow
  background.wantsLayer = true; background.layer?.cornerRadius = 12; background.layer?.masksToBounds = true
  if !settings.translucent { background.material = .windowBackground; background.blendingMode = .withinWindow }
  let foregroundHex = compact ? settings.statusForeground : settings.switchForeground
  let backgroundHex = compact ? settings.statusBackground : settings.switchBackground
  func color(_ hex: String?) -> NSColor? {
   guard let hex, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
   return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
  }
  if let customBackground = color(backgroundHex) {
   let tint = NSView(frame: background.bounds)
   tint.autoresizingMask = [.width, .height]
   tint.wantsLayer = true
   tint.layer?.backgroundColor = customBackground.withAlphaComponent(settings.translucent ? 0.7 : 1).cgColor
   background.addSubview(tint)
  }
  let label = NSTextField(labelWithString: title)
  if let foreground = color(foregroundHex) { label.textColor = foreground }
  let fontSize = compact ? (settings.statusFontSize ?? 13) : (settings.switchFontSize ?? 30)
  let fontName = compact ? settings.statusFontName : settings.switchFontName
  label.font = fontName.flatMap { NSFont(name: $0, size: fontSize) } ?? .systemFont(ofSize: fontSize, weight: .medium)
  label.alignment = .center
  let lineHeight = min(size.height, ceil(label.font!.ascender - label.font!.descender + label.font!.leading + 4))
  label.frame = NSRect(x: 12, y: (size.height - lineHeight) / 2, width: max(0, size.width - 24), height: lineHeight)
  background.addSubview(label); panel.contentView = background
  return panel
 }
 deinit { startupHideWork?.cancel(); startupPanels.forEach { $0.orderOut(nil) }; hideWork?.cancel(); (switchPanels + statusPanels).forEach { $0.orderOut(nil) } }
}
