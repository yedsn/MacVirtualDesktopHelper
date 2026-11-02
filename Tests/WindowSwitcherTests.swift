import AppKit
@main struct WindowSwitcherTests {
 static func main() throws {
  func window(_ id: UInt32) -> DesktopWindow {
   DesktopWindow(id: id, ownerName: "Test", title: String(id), bundleID: "test.app", pid: 1, spaceID: 10, displayUUID: "display", isOnScreen: true, isSticky: false, icon: nil)
  }
  let windows = (1...3).map { window(UInt32($0)) }
  let session = WindowSwitcherSession(candidates: windows, currentID: 1)
  precondition(session.selected?.id == 2)
  session.advance(); precondition(session.selected?.id == 3)
  session.advance(); precondition(session.selected?.id == 1)
  session.advance(reverse: true); precondition(session.selected?.id == 3)
  precondition(session.commit()?.id == 3 && session.commit() == nil)
  let cancelled = WindowSwitcherSession(candidates: windows, currentID: 1)
  cancelled.cancel(); precondition(cancelled.commit() == nil)
  let empty = WindowSwitcherSession(candidates: [], currentID: nil)
  empty.advance(); precondition(empty.commit() == nil)
  let single = WindowSwitcherSession(candidates: [window(1)], currentID: 1)
  single.advance(reverse: true); precondition(single.selected?.id == 1)
  var unavailable = window(2); unavailable.isAccessibilityUnavailable = true
  let skipping = WindowSwitcherSession(candidates: [window(1), unavailable, window(3)], currentID: 1)
  precondition(skipping.candidates.map { $0.id } == [1, 3] && skipping.selected?.id == 3)
  skipping.advance(reverse: true); precondition(skipping.selected?.id == 1)
  let disabled = WindowSwitcherSession(candidates: [unavailable], currentID: nil)
  precondition(disabled.candidates.isEmpty && disabled.selected == nil && disabled.commit() == nil)
  let firstReverse = WindowSwitcherSession(candidates: [window(1), unavailable, window(3)], currentID: 1, reverse: true)
  precondition(firstReverse.selected?.id == 3)
  let noFocusReverse = WindowSwitcherSession(candidates: windows, currentID: nil, reverse: true)
  precondition(noFocusReverse.selected?.id == 3)
  let duplicateHistory = WindowSwitcherSession(candidates: windows, currentID: 1, mostRecentIDs: [1, 1, 2, 2])
  precondition(duplicateHistory.candidates.count == 3 && duplicateHistory.selected?.id == 2)
  let staleHistory = WindowSwitcherSession(candidates: windows, currentID: 2, mostRecentIDs: [1, 3, 2])
  precondition(staleHistory.candidates.map { $0.id } == [2, 1, 3])
  precondition(staleHistory.selected?.id == 1)
  var old = ApplicationSettings(); old.theme = "dark"
  let encoder = JSONEncoder()
  let decoded = try JSONDecoder().decode(ApplicationSettings.self, from: encoder.encode(old))
  precondition(decoded.windowSwitcherEnabled != true && decoded.theme == "dark")
  var enabled = decoded; enabled.windowSwitcherEnabled = true
  enabled.windowSwitcherModifiers = 2048
  let reloaded = try JSONDecoder().decode(ApplicationSettings.self, from: encoder.encode(enabled))
  precondition(reloaded.windowSwitcherEnabled == true && reloaded.windowSwitcherModifiers == 2048 && reloaded.theme == "dark")
  var state = RuleState(); state.settings = enabled
  try RuleStore.validate(state)
  state.settings?.hotKeys = [HotKeyBinding(action: "manager", keyCode: 48, modifiers: 2048 | 512)]
  do { try RuleStore.validate(state); preconditionFailure("Reverse binding conflict accepted") } catch {}
  state.settings?.hotKeys = nil
  state.settings?.windowSwitcherModifiers = 512
  do { try RuleStore.validate(state); preconditionFailure("Shift-only hold accepted") } catch {}
  state.settings?.windowSwitcherModifiers = 2048
  state.settings?.windowSwitcherKeyCode = 2
  do { try RuleStore.validate(state); preconditionFailure("Non-Tab key accepted") } catch {}
  print("PASS: switcher wrap, reverse, cancel, single commit and configuration")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try RuleStore(url: directory.appendingPathComponent("state.json"))
  try store.update { $0.settings = old }
  let originalData = try Data(contentsOf: store.url)
  store.prepareSettings = { _ in throw NSError(domain: "RegistrationRejected", code: 1) }
  do { try store.update { $0.settings?.windowSwitcherEnabled = true }; preconditionFailure("Rejected registration saved") } catch {}
  precondition(store.state.settings?.windowSwitcherEnabled != true)
  let preservedData = try Data(contentsOf: store.url)
  precondition(preservedData == originalData)
  store.prepareSettings = nil
  var restored = false
  store.rollbackSettings = { settings in restored = settings.theme == "dark" }
  try FileManager.default.removeItem(at: store.url)
  try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
  do { try store.update { $0.settings?.windowSwitcherEnabled = true }; preconditionFailure("Directory write succeeded") } catch {}
  precondition(restored && store.state.settings?.windowSwitcherEnabled != true)
  print("PASS: registration rejection preserves disk and write failure restores registration settings")
 }
}
