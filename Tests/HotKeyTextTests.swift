import Foundation
@main struct HotKeyTextTests {
 static func main() throws {
  let source = (0...127).map { HotKeyBinding(action: "manager", keyCode: UInt32($0), modifiers: 256 | 2048) }
  let decoded = try HotKeyText.parse(HotKeyText.render(source))
  precondition(decoded.map { $0.keyCode } == source.map { $0.keyCode })
  precondition(decoded.allSatisfy { $0.modifiers == 2304 && $0.action == "manager" })
  let mixed = try HotKeyText.parse("manager=option+a\ndesktop:9=Control+Shift+9\nforward=Command+F12")
  precondition(mixed.count == 3 && mixed[0].keyCode == 0 && mixed[2].keyCode == 111)
  for invalid in ["manager=D", "manager=Option+Option+D", "manager=Option+D\nforward=Option+D", "desktop:10=Option+1", "manager=Option+KeyCode:128", "other=Option+A"] {
   do { _ = try HotKeyText.parse(invalid); preconditionFailure("Accepted invalid shortcut") } catch {}
  }
  let empty = try HotKeyText.parse("\n ").isEmpty
  precondition(empty)
  print("PASS: all 128 key codes round-trip; common keys, case, invalid and duplicate shortcuts")
 }
}
