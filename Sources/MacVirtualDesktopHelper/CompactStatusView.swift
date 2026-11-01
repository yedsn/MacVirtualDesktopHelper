import AppKit

/// A single menu extra with individually clickable desktop cells.
final class CompactStatusView: NSView {
 var spaces: [DesktopSpace] = [] { didSet { needsDisplay = true } }
 var selectSpace: ((DesktopSpace) -> Void)?
 var showManager: (() -> Void)?
 var showMenu: ((NSEvent) -> Void)?
 var clickScreenLocation: (() -> NSPoint)?
 var iconSpacing: CGFloat = 8 { didSet { needsDisplay = true } }
 var foreground: NSColor?
 var symbolForeground: NSColor?
 var background: NSColor?
 var fontName: String?
 var fontSize: CGFloat = 11
 var navigation = false
 var showNameInitial = false
 var hideNavigationAtBounds = false
 private enum Entry { case desktop(DesktopSpace), name(DesktopSpace), arrow(String, DesktopSpace?) }
 private var entries: [Entry] {
  guard navigation, let index = spaces.firstIndex(where: { $0.isCurrent }) else { return spaces.map { .desktop($0) } }
  let displaySpaces = spaces.filter { $0.displayUUID == spaces[index].displayUUID }
  guard let current = displaySpaces.firstIndex(where: { $0.isCurrent }) else { return [] }
  let previous = current > 0 ? displaySpaces[current - 1] : nil
  let next = current + 1 < displaySpaces.count ? displaySpaces[current + 1] : nil
  var result: [Entry] = []
  if previous != nil || !hideNavigationAtBounds { result.append(.arrow("‹", previous)) }
  result.append(.desktop(displaySpaces[current]))
  if showNameInitial { result.append(.name(displaySpaces[current])) }
  if next != nil || !hideNavigationAtBounds { result.append(.arrow("›", next)) }
  return result
 }
 static func color(_ hex: String?) -> NSColor? {
  guard let hex, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
  return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
 }
 private var cellWidth: CGFloat { 18 + iconSpacing }
 var requiredWidth: CGFloat { CGFloat(entries.count + 1) * cellWidth + 6 }
 override func draw(_ dirtyRect: NSRect) {
  let color = foreground ?? NSColor.labelColor
  let symbolColor = symbolForeground ?? color
  if let background {
   background.setFill()
   NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4).fill()
  }
  for (index, entry) in entries.enumerated() {
   let box = NSRect(x: 3 + iconSpacing / 2 + CGFloat(index + 1) * cellWidth, y: (bounds.height - 18) / 2, width: 18, height: 18)
   let space: DesktopSpace
   let caption: String
   switch entry {
   case .desktop(let desktop): space = desktop; caption = String(desktop.index + 1)
   case .name(let desktop): space = desktop; caption = String(desktop.title.prefix(1))
   case .arrow:
    if case let .arrow(symbol, target) = entry {
     let text = symbol as NSString
     let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: target == nil ? symbolColor.withAlphaComponent(0.35) : symbolColor]
     let size = text.size(withAttributes: attributes)
     text.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attributes)
    }
    continue
   }
   color.setStroke()
   let path = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
   if space.isCurrent { color.setFill(); path.fill() } else { path.lineWidth = 1; path.stroke() }
   let text = caption as NSString
   let preferredFont = fontName.flatMap { NSFont(name: $0, size: fontSize) } ?? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
   let rawSize = text.size(withAttributes: [.font: preferredFont])
   let font = rawSize.width > 16 ? NSFont(descriptor: preferredFont.fontDescriptor, size: fontSize * 16 / rawSize.width) ?? preferredFont : preferredFont
   let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: space.isCurrent ? (background ?? NSColor.windowBackgroundColor) : color]
   let size = text.size(withAttributes: attributes)
   text.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attributes)
  }
  symbolColor.setFill()
  let x = 4 + iconSpacing / 2
  let y = (bounds.height - 16) / 2
  for dx in [0.0, 9.0] { for dy in [0.0, 9.0] { NSRect(x: x + dx, y: y + dy, width: 7, height: 7).fill() } }
 }
 override func mouseDown(with event: NSEvent) {
  if event.modifierFlags.contains(.control) { showMenu?(event); return }
  // Ordinary windows preserve event coordinates; NSStatusBar supplies its
  // screen-position provider because its synthetic event targets the center.
  let location: NSPoint
  if let clickScreenLocation, let window {
   // NSStatusBar can synthesize a click at the status item center.
   // Capture the pointer at delivery for this host instead of that midpoint.
   location = window.convertPoint(fromScreen: clickScreenLocation())
  } else if let eventWindow = event.window, let window, eventWindow !== window {
   location = window.convertPoint(fromScreen: eventWindow.convertPoint(toScreen: event.locationInWindow))
  } else { location = event.locationInWindow }
  let point = convert(location, from: nil)
  guard bounds.contains(point), point.x >= 3 else { return }
  let index = Int((point.x - 3) / cellWidth)
  if index == 0 { showManager?() }
  else if entries.indices.contains(index - 1) {
   switch entries[index - 1] {
   case .desktop(let space):
    if navigation { showManager?() } else { selectSpace?(space) }
   case .name: showManager?()
   case .arrow(_, let target): if let target { selectSpace?(target) }
   }
  }
 }
 override func rightMouseDown(with event: NSEvent) { showMenu?(event) }
 override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
