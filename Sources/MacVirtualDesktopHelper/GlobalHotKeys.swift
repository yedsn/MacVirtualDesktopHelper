import AppKit
import Carbon

final class GlobalHotKeys {
 private var handler: EventHandlerRef?
 private var registrations: [EventHotKeyRef] = []
 private var actions: [UInt32: String] = [:]
 var perform: ((String) -> Void)?
 init() {
  var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
   guard let context, let event else { return OSStatus(eventNotHandledErr) }
   let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
   var id = EventHotKeyID()
   let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
   if result == noErr, let action = owner.actions[id.id] { owner.perform?(action) }
   return noErr
  }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
 }
 func reload(_ bindings: [HotKeyBinding]) -> [String] {
  var errors: [String] = []
  var seen = Set<String>()
  for binding in bindings {
   let identity = String(binding.keyCode) + ":" + String(binding.modifiers)
   guard binding.modifiers != 0, binding.keyCode <= 127,
    binding.modifiers & ~UInt32(256 | 512 | 2048 | 4096) == 0,
    seen.insert(identity).inserted else {
    errors.append(binding.action + "：按键无效或重复".localized); continue
   }
  }
  // Invalid input must not tear down the last working configuration.
  guard errors.isEmpty else { return errors }
  registrations.forEach { UnregisterEventHotKey($0) }
  registrations.removeAll(); actions.removeAll()
  for (index, binding) in bindings.enumerated() {
   var ref: EventHotKeyRef?
   let id = UInt32(index + 1)
   let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x4D564448, id: id), GetApplicationEventTarget(), 0, &ref)
   if status == noErr, let ref { registrations.append(ref); actions[id] = binding.action }
   else { errors.append(binding.action + "：注册冲突或系统拒绝（".localized + String(status) + "）") }
  }
  return errors
 }
 deinit {
  registrations.forEach { UnregisterEventHotKey($0) }
  if let handler { RemoveEventHandler(handler) }
 }
}
