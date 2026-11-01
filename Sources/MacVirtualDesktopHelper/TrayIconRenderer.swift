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
}
