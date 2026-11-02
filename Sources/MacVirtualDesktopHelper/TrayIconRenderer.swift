import AppKit

// Palette and geometry follow Windows Util/Icons.cs and AppForm.UpdateDesktopNotifyIcons.
enum TrayIconRenderer {
 static let blue = NSColor(srgbRed: 0, green: 120.0 / 255, blue: 212.0 / 255, alpha: 1)
 static func desktop(number: Int, current: Bool) -> NSImage {
  let size = NSSize(width: 18, height: 18)
  let image = NSImage(size: size, flipped: false) { rect in
   let background = current ? blue : NSColor(srgbRed: 0.30, green: (120.0 * 0.7 + 255 * 0.3) / 255, blue: (212.0 * 0.7 + 255 * 0.3) / 255, alpha: 1)
   background.setFill()
   rect.fill()
   let text = String(String(number).prefix(2)) as NSString
   let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: number < 10 ? 11 : 9, weight: .regular), .foregroundColor: NSColor.white]
   let measured = text.size(withAttributes: attributes)
   text.draw(at: NSPoint(x: (rect.width - measured.width) / 2, y: (rect.height - measured.height) / 2), withAttributes: attributes)
   return true
  }
  image.isTemplate = false
  return image
 }
 static func manager() -> NSImage {
  let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
   blue.withAlphaComponent(225.0 / 255).setFill()
   let pane = 18.0 * 0.94 / 2
   let step = pane + 18.0 * 0.06
   for x in [0.0, step] { for y in [0.0, step] { NSRect(x: x, y: y, width: pane, height: pane).fill() } }
   return true
  }
  image.isTemplate = false
  return image
 }

 static func applicationIcon() -> NSImage {
  let size = 512
  guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: size * 4, bitsPerPixel: 32),
    let context = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage() }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()
  blue.withAlphaComponent(225.0 / 255).setFill()
  let pane = CGFloat(size) * 0.94 / 2
  let step = pane + CGFloat(size) * 0.06
  for x in [0.0, step] { for y in [0.0, step] {
   NSRect(x: x, y: y, width: pane, height: pane).fill()
  }}
  NSGraphicsContext.restoreGraphicsState()
  let image = NSImage(size: NSSize(width: size, height: size))
  image.addRepresentation(rep)
  image.isTemplate = false
  return image
 }

 /// Keeps the Dock entry stable: either the app always appears with its icon,
 /// or it stays a menu-bar-only agent. Toggling the policy on every window
 /// close makes macOS rebuild the Dock tile and briefly show a blank default.
 static func applyDockPolicy(showDockIcon: Bool) {
  NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
  if showDockIcon { NSApp.applicationIconImage = applicationIcon() }
 }
}
