import AppKit

@main
struct CompactStatusViewTests {
 static func main() {
  _ = NSApplication.shared
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 24), styleMask: .borderless, backing: .buffered, defer: false)
  let view = CompactStatusView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
  window.contentView = view
  view.iconSpacing = 12
  view.spaces = (0..<5).map { DesktopSpace(id: UInt64($0 + 1), uuid: "space-($0)", displayUUID: "display", displayIndex: 0, index: $0, displayCount: 1, isCurrent: $0 == 4) }
  var selected: [UInt64] = []
  var manager = 0
  var menus = 0
  view.selectSpace = { selected.append($0.id) }
  view.showManager = { manager += 1 }
  view.showMenu = { _ in menus += 1 }
  func click(_ x: CGFloat, flags: NSEvent.ModifierFlags = [], right: Bool = false) {
   let event = NSEvent.mouseEvent(with: right ? .rightMouseDown : .leftMouseDown, location: NSPoint(x: x, y: 12), modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
   if right { view.rightMouseDown(with: event) } else { view.mouseDown(with: event) }
  }
  // Pointer position deliberately differs from every captured event.
  CGWarpMouseCursorPosition(CGPoint(x: 600, y: 400))
  for x: CGFloat in [48, 168, 108, 78] { click(x) }
  precondition(selected == [1, 5, 3, 2] && menus == 0)
  click(48, flags: .control)
  click(48, right: true)
  precondition(menus == 2 && selected.count == 4)
  click(-2)
  precondition(manager == 0)
  view.navigation = true
  view.showNameInitial = true
  click(78)
  click(108)
  precondition(manager == 2 && selected.count == 4)
  click(48)
  precondition(selected.last == 4)
  view.showNavigationArrows = false
  precondition(view.requiredWidth == 96)
  click(48)
  click(78)
  precondition(manager == 4 && selected.last == 4)
  view.navigation = false
  view.clickScreenLocation = { window.convertPoint(toScreen: NSPoint(x: 168, y: 12)) }
  click(101) // Synthetic status-item center must not select the middle cell.
  precondition(selected.last == 5)
  print("PASS: queued event coordinates, repeated left clicks, right/control clicks and navigation manager actions")
 }
}
