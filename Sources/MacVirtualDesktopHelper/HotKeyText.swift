import Foundation

/// Lossless text representation shared by the settings editor and its validator.
enum HotKeyText {
 static let keys: [String: UInt32] = [
  "A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,
  "B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,
  "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,
  "O":31,"U":32,"I":34,"P":35,"Return":36,"L":37,"J":38,"K":40,
  "N":45,"M":46,"Tab":48,"Space":49,"`":50,"Delete":51,"Escape":53,
  "F1":122,"F2":120,"F3":99,"F4":118,"F5":96,"F6":97,"F7":98,"F8":100,
  "F9":101,"F10":109,"F11":103,"F12":111,"Home":115,"End":119,
  "PageUp":116,"PageDown":121,"Left":123,"Right":124,"Down":125,"Up":126
 ]
 static let modifiers: [(String, UInt32)] = [("Command",256),("Shift",512),("Option",2048),("Control",4096)]
 static func render(_ bindings: [HotKeyBinding]) -> String {
  bindings.map { binding in
   let names = modifiers.filter { binding.modifiers & $0.1 != 0 }.map { $0.0 }
   let key = keys.first { $0.value == binding.keyCode }?.key ?? "KeyCode:" + String(binding.keyCode)
   return binding.action + "=" + (names + [key]).joined(separator: "+")
  }.joined(separator: "\n")
 }
 static func parse(_ source: String) throws -> [HotKeyBinding] {
  var bindings: [HotKeyBinding] = []
  var combinations = Set<String>()
  for line in source.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
   let parts = line.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
   guard parts.count == 2 else { throw invalid() }
   let action = parts[0]
   let desktop = action.hasPrefix("desktop:") ? Int(action.dropFirst(8)) : nil
   guard ["manager","forward","backward","previous"].contains(action) || (1...9).contains(desktop ?? 0) else { throw invalid() }
   let tokens = parts[1].components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
   guard let last = tokens.last else { throw invalid() }
   let key = keys.first { $0.key.lowercased() == last.lowercased() }?.value ?? (last.hasPrefix("KeyCode:") ? UInt32(last.dropFirst(8)) : nil)
   guard let key, key <= 127 else { throw invalid() }
   var mask: UInt32 = 0
   for token in tokens.dropLast() {
    guard let flag = modifiers.first(where: { $0.0.lowercased() == token.lowercased() })?.1,
     mask & flag == 0 else { throw invalid() }
    mask |= flag
   }
   guard mask != 0, combinations.insert(String(key) + ":" + String(mask)).inserted else { throw invalid() }
   bindings.append(HotKeyBinding(action: action, keyCode: key, modifiers: mask))
  }
  return bindings
 }
 private static func invalid() -> NSError {
  NSError(domain: "HotKeys", code: 1, userInfo: [NSLocalizedDescriptionKey: "快捷键格式无效、修饰键重复或按键重复，请按示例填写。"])
 }
}
