import AppKit
@main struct WindowListKeyboardTests {
 static func main() {
  _ = NSApplication.shared
  let window = NSWindow(contentRect: NSRect(x:0,y:0,width:400,height:300), styleMask:[.titled], backing:.buffered, defer:false)
  let table = WindowListTable(frame:NSRect(x:0,y:0,width:400,height:300))
  window.contentView = table
  table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("test")))
  window.makeKeyAndOrderFront(nil)
  precondition(window.makeFirstResponder(table))
  var locks = 0
  table.toggleLock = { locks += 1 }
  func event(_ flags: NSEvent.ModifierFlags) -> NSEvent {
   NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"l",charactersIgnoringModifiers:"l",isARepeat:false,keyCode:37)!
  }
  precondition(table.performKeyEquivalent(with:event(.command)))
  precondition(locks == 1)
  _ = table.performKeyEquivalent(with:event([.command,.shift]))
  precondition(locks == 1)
  let field = NSTextField(frame:.zero)
  table.addSubview(field)
  window.makeFirstResponder(field)
  _ = table.performKeyEquivalent(with:event(.command))
  precondition(locks == 1, "Inactive table intercepted another responder's shortcut")
  print("PASS: focused list handles Command+L key equivalents without intercepting other responders or modifiers")
 }
}
