import AppKit

@main struct GlobalHotKeyTests {
 static func main() {
  _ = NSApplication.shared
  let first = GlobalHotKeys()
  let binding = HotKeyBinding(action: "manager", keyCode: 2, modifiers: 256 | 512 | 2048 | 4096)
  precondition(first.reload([binding]).isEmpty)
  let second = GlobalHotKeys()
  precondition(!second.reload([binding]).isEmpty)
  precondition(first.reload([]).isEmpty)
  precondition(second.reload([binding]).isEmpty)
  precondition(!second.reload([HotKeyBinding(action: "manager", keyCode: 2, modifiers: 0)]).isEmpty)
  precondition(!first.reload([binding]).isEmpty, "Invalid reload released the working shortcut")
  precondition(!second.reload([HotKeyBinding(action: "manager", keyCode: 2, modifiers: 1)]).isEmpty)
  precondition(!first.reload([binding]).isEmpty, "Unknown modifier released the working shortcut")
  precondition(!second.reload([binding, binding]).isEmpty)
  precondition(!first.reload([binding]).isEmpty, "Duplicate reload released the working shortcut")
  precondition(second.reload([]).isEmpty)
  precondition(first.reload([binding]).isEmpty)
  print("PASS: registration, conflict detection, unregister; invalid and duplicate reload preserve working shortcuts")
 }
}
