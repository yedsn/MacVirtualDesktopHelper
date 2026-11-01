import Foundation

@main struct RuleStoreTests {
 static func main() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("state.json")
  let store = try RuleStore(url: url)
  let exact = WindowRule(bundleID: "test.app", applicationPath: "/Applications/Test.app", title: "Document A")
  try store.update { $0.cleanupRules = [exact] }
  let loaded = try RuleStore(url: url)
  precondition(loaded.state.cleanupRules.count == 1)
  precondition(exact.matches(bundleID: "test.app", applicationPath: "/Applications/Test.app", title: "Document A"))
  precondition(!exact.matches(bundleID: "other.app", applicationPath: "/Applications/Test.app", title: "Document A"))
  precondition(!exact.matches(bundleID: "test.app", applicationPath: "/Applications/Other.app", title: "Document A"))
  precondition(!exact.matches(bundleID: "test.app", applicationPath: "/Applications/Test.app", title: "document A"))
  let bundleOnly = WindowRule(bundleID: "test.app", applicationPath: "", title: "Document A")
  let pathOnly = WindowRule(bundleID: "", applicationPath: "/Applications/Test.app", title: "Document A")
  precondition(bundleOnly.matches(bundleID: "test.app", applicationPath: "/Moved/Test.app", title: "Document A"))
  precondition(pathOnly.matches(bundleID: "", applicationPath: "/Applications/Test.app", title: "Document A"))
  precondition(WindowRule(bundleID: "", applicationPath: "", title: "Document A").matchResult(bundleID: "", applicationPath: "", title: "Document A") == .indeterminate)
  let before = try Data(contentsOf: url)
  do {
   try store.update { state in
    state.cleanupRules.removeAll()
    throw NSError(domain: "TestMutation", code: 1)
   }
   fatalError("Throwing mutation accepted")
  } catch {}
  precondition(store.state.cleanupRules.count == 1)
  let afterThrow = try Data(contentsOf: url)
  precondition(afterThrow == before)
  do {
   try store.update { $0.cleanupRules[0].titleIsRegex = true; $0.cleanupRules[0].title = "[" }
   fatalError("Invalid regex accepted")
  } catch { }
  let afterInvalid = try Data(contentsOf: url)
  precondition(afterInvalid == before)
  precondition(store.state.cleanupRules[0].title == "Document A")
  do {
   try store.update { $0.cleanupRules.append(exact) }
   fatalError("Duplicate rule accepted")
  } catch { }
  let afterDuplicate = try Data(contentsOf: url)
  precondition(afterDuplicate == before)
  print("PASS: persistence, identity, invalid regex and duplicate rollback")
  for language in ["zh-CN", "en"] {
   var state = RuleState()
   state.settings = ApplicationSettings()
   state.settings?.language = language
   try RuleStore.validate(state)
  }
  do {
   try store.update { state in
    state.settings = ApplicationSettings()
    state.settings?.language = "unknown"
   }
   fatalError("Unknown language accepted")
  } catch {}
  precondition(store.state.settings == nil)
  let afterInvalidLanguage = try Data(contentsOf: url)
  precondition(afterInvalidLanguage == before)
  print("PASS: supported languages and unknown-language atomic rollback")
  var pattern = exact
  pattern.title = "^Document .*"
  pattern.titleIsRegex = true
  precondition(pattern.matchResult(bundleID: "test.app", applicationPath: "/Applications/Test.app", title: "Document A", timeLimit: 0) == .indeterminate)
  precondition(pattern.matchResult(bundleID: "other.app", applicationPath: "/Applications/Test.app", title: "Document A", timeLimit: 0) == .notMatched)
  let first = RuleWindowIdentity(id: 1, bundleID: "test.app", applicationPath: "/Applications/Test.app", title: "Document A", spaceUUID: "space-3", displayUUID: "display", desktopIndex: 2)
  let update = DesktopRuleMatcher.update(rules: [pattern], windows: [first])
  precondition(update.changes.count == 1)
  precondition(update.changes[0].rule.title == pattern.title && update.changes[0].rule.titleIsRegex)
  precondition(update.changes[0].rule.id == pattern.id && update.changes[0].rule.targetIndex == 2)
  let previewChange = update.changes[0]
  precondition(previewChange.agrees(with: DesktopRuleMatcher.update(rules: [pattern], windows: [first]).changes[0]))
  var changedTarget = previewChange.rule
  changedTarget.targetSpaceUUID = "different-space"
  precondition(!previewChange.agrees(with: DesktopRuleChange(windowID: first.id, rule: changedTarget, isNew: false)))
  var replacement = previewChange.rule
  replacement.id = UUID()
  precondition(!previewChange.agrees(with: DesktopRuleChange(windowID: first.id, rule: replacement, isNew: false)))
  let newPreview = DesktopRuleMatcher.update(rules: [], windows: [first]).changes[0]
  let newFresh = DesktopRuleMatcher.update(rules: [], windows: [first]).changes[0]
  precondition(newPreview.rule.id != newFresh.rule.id && newPreview.agrees(with: newFresh))
  precondition(!previewChange.agrees(with: newFresh))
  precondition(DesktopRuleMatcher.update(rules: [pattern], windows: []).changes.isEmpty)
  let second = RuleWindowIdentity(id: 2, bundleID: first.bundleID, applicationPath: first.applicationPath, title: "Document B", spaceUUID: "space-1", displayUUID: "display", desktopIndex: 0)
  let conflict = DesktopRuleMatcher.update(rules: [pattern], windows: [first, second])
  precondition(conflict.changes.isEmpty && conflict.ambiguousWindowIDs.count == 2)
  var evaluations = 0
  let uncertain = DesktopRuleMatcher.update(rules: [pattern], windows: [first, second]) { _, window in
   evaluations += 1
   return window.id == first.id ? .matched : .indeterminate
  }
  precondition(uncertain.changes.isEmpty && uncertain.ambiguousWindowIDs == Set([first.id, second.id]))
  precondition(evaluations == 2)
  let uncertainNew = DesktopRuleMatcher.update(rules: [pattern], windows: [second]) { _, _ in .indeterminate }
  precondition(uncertainNew.changes.isEmpty && uncertainNew.ambiguousWindowIDs == Set([second.id]))
  precondition(DesktopRuleMatcher.uniqueWindow(for: pattern, rules: [pattern, exact], windows: [first]) == nil)
  let absent = DesktopRuleMatcher.update(rules: [pattern], windows: [])
  precondition(absent.changes.isEmpty)
  for invalid in [
   RuleWindowIdentity(id: 10, bundleID: "test.app", applicationPath: "", title: "A", spaceUUID: "", displayUUID: "display", desktopIndex: 0),
   RuleWindowIdentity(id: 11, bundleID: "test.app", applicationPath: "", title: "A", spaceUUID: "space", displayUUID: "", desktopIndex: 0),
   RuleWindowIdentity(id: 12, bundleID: "test.app", applicationPath: "", title: "A", spaceUUID: "space", displayUUID: "display", desktopIndex: -1),
   RuleWindowIdentity(id: 13, bundleID: "", applicationPath: "", title: "A", spaceUUID: "space", displayUUID: "display", desktopIndex: 0)
  ] {
   let rejected = DesktopRuleMatcher.update(rules: [], windows: [invalid])
   precondition(rejected.changes.isEmpty && rejected.ambiguousWindowIDs.contains(invalid.id))
  }
  print("PASS: regex preservation, target update, bidirectional ambiguity and absent-window preservation")
  try store.capture(name: "manual")
  let manual = store.state.snapshots[0]
  for index in 0..<4 { try store.capture(name: "auto " + String(index), automatic: true, maximumAutomatic: 3) }
  precondition(store.state.snapshots.filter(\.automatic).count == 3)
  precondition(store.state.snapshots.contains { $0.id == manual.id })
  try store.update { $0.cleanupRules = [] }
  try store.restore(id: manual.id)
  precondition(store.state.cleanupRules.count == 1)
  print("PASS: snapshot restoration and automatic-only retention")
  let pairStore = try RuleStore(url: directory.appendingPathComponent("paired.json"))
  var savedDesktop = pattern
  savedDesktop.targetSpaceUUID = "original-space"
  savedDesktop.targetDisplayUUID = "original-display"
  savedDesktop.targetIndex = 2
  try pairStore.update {
   $0.cleanupRules = [exact]
   $0.desktopRules = [savedDesktop]
   $0.settings = ApplicationSettings(theme: "light")
  }
  try pairStore.capture(name: "paired")
  let pairID = pairStore.state.snapshots[0].id
  let replacementRule = WindowRule(bundleID: "replacement.app", applicationPath: "", title: "Replacement")
  try pairStore.update {
   $0.cleanupRules = [replacementRule]
   $0.desktopRules = [replacementRule]
   $0.settings?.theme = "dark"
  }
  try pairStore.restore(id: pairID)
  let restoredPair = try RuleStore(url: pairStore.url)
  precondition(restoredPair.state.cleanupRules.map(\.id) == [exact.id])
  precondition(restoredPair.state.desktopRules.map(\.id) == [savedDesktop.id])
  precondition(restoredPair.state.desktopRules[0].targetSpaceUUID == "original-space")
  precondition(restoredPair.state.desktopRules[0].titleIsRegex)
  precondition(restoredPair.state.settings?.theme == "dark")
  print("PASS: paired snapshot replaces both rule sets on disk and preserves current application settings")
  try store.update {
   $0.snapshotSettings = SnapshotSettings(enabled: true, intervalMinutes: 45, maximumCount: 4)
   $0.settings = ApplicationSettings(theme: "dark", desktopDisplayMode: "navigation", windowManager: "built-in", hideNavigationAtBounds: true)
   $0.settings?.overlay = OverlaySettings(showStatus: true, duration: 3, position: "bottom")
   $0.settings?.restoreWindowFocus = true
   $0.settings?.menuIconSpacing = 12
   $0.settings?.menuForeground = "#FFFFFF"
   $0.settings?.menuBackground = "#202020"
   $0.settings?.menuFontName = "Menlo-Regular"
   $0.settings?.menuFontSize = 12
   $0.settings?.menuSymbolForeground = "#AABBCC"
   $0.settings?.showDockIcon = false
   $0.settings?.overviewFontSize = 16
   $0.settings?.frostedWindow = false
   $0.settings?.overlay?.position = "bottomleft"
   $0.settings?.overlay?.statusPosition = "topright"
   $0.settings?.overlay?.statusAllDisplays = false
   $0.settings?.overlay?.statusTranslucent = false
   $0.settings?.overlay?.statusAnimate = false
  }
  let backupURL = directory.appendingPathComponent("backup.json")
  try ConfigurationBackupService.export(store: store, to: backupURL)
  let backup = try ConfigurationBackupService.preview(from: backupURL)
  let other = try RuleStore(url: directory.appendingPathComponent("other.json"))
  try ConfigurationBackupService.restore(backup, store: other)
  precondition(other.state.cleanupRules.count == store.state.cleanupRules.count)
  precondition(other.state.snapshots.count == store.state.snapshots.count)
  precondition(other.state.snapshotSettings?.intervalMinutes == 45)
  precondition(other.state.settings?.theme == "dark" && other.state.settings?.desktopDisplayMode == "navigation")
  precondition(other.state.settings?.overlay?.duration == 3 && other.state.settings?.overlay?.showStatus == true)
  precondition(other.state.settings?.restoreWindowFocus == true)
  precondition(other.state.settings?.menuIconSpacing == 12)
  precondition(other.state.settings?.menuSymbolForeground == "#AABBCC")
  do {
   try other.update { $0.settings?.menuSymbolForeground = "invalid" }
   fatalError("Invalid symbol color accepted")
  } catch {}
  precondition(other.state.settings?.menuSymbolForeground == "#AABBCC")
  precondition(other.state.settings?.showDockIcon == false && other.state.settings?.frostedWindow == false)
  precondition(other.state.settings?.overviewFontSize == 16)
  do {
   try other.update { $0.settings?.overviewFontSize = 100 }
   fatalError("Invalid overview font size accepted")
  } catch {}
  precondition(other.state.settings?.overviewFontSize == 16)
  precondition(other.state.settings?.menuForeground == "#FFFFFF" && other.state.settings?.menuBackground == "#202020")
  precondition(other.state.settings?.menuFontName == "Menlo-Regular" && other.state.settings?.menuFontSize == 12)
  do {
   try other.update { $0.settings?.menuFontSize = 100 }
   fatalError("Invalid menu font size accepted")
  } catch { }
  precondition(other.state.settings?.menuFontSize == 12)
  do {
   try other.update { $0.settings?.menuForeground = "white" }
   fatalError("Invalid menu color accepted")
  } catch { }
  precondition(other.state.settings?.menuForeground == "#FFFFFF")
  precondition(other.state.settings?.overlay?.position == "bottomleft")
  precondition(other.state.settings?.overlay?.statusPosition == "topright")
  precondition(other.state.settings?.overlay?.statusAllDisplays == false)
  precondition(other.state.settings?.overlay?.statusTranslucent == false)
  precondition(other.state.settings?.overlay?.statusAnimate == false)
  for position in OverlaySettings.positions {
   var candidate = other.state
   candidate.settings?.overlay?.position = position
   candidate.settings?.overlay?.statusPosition = position
   try RuleStore.validate(candidate)
  }
  for invalidSpacing in [-1.0, 25.0, Double.infinity, Double.nan] {
   do {
    try other.update { $0.settings?.menuIconSpacing = invalidSpacing }
    fatalError("Invalid icon spacing accepted")
   } catch { }
   precondition(other.state.settings?.menuIconSpacing == 12)
  }
  do {
   try other.update { $0.settings?.overlay?.statusPosition = "invalid" }
   fatalError("Invalid status overlay position accepted")
  } catch { }
  precondition(other.state.settings?.overlay?.statusPosition == "topright")
  let otherBefore = try Data(contentsOf: other.url)
  let malformedURL = directory.appendingPathComponent("malformed.json")
  try Data("{broken".utf8).write(to: malformedURL)
  do {
   _ = try ConfigurationBackupService.preview(from: malformedURL)
   fatalError("Malformed backup accepted")
  } catch { precondition((error as NSError).code == 1) }
  var future = backup
  future.version = 999
  let futureURL = directory.appendingPathComponent("future.json")
  try JSONEncoder().encode(future).write(to: futureURL)
  do {
   _ = try ConfigurationBackupService.preview(from: futureURL)
   fatalError("Future backup accepted")
  } catch { precondition((error as NSError).code == 2) }
  do {
   try ConfigurationBackupService.restore(future, store: other)
   fatalError("Future restore accepted")
  } catch { precondition((error as NSError).localizedDescription.contains("版本")) }
  let afterRejectedFormats = try Data(contentsOf: other.url)
  precondition(afterRejectedFormats == otherBefore)
  var invalid = backup
  invalid.state.snapshotSettings = SnapshotSettings(intervalMinutes: 0)
  do { try ConfigurationBackupService.restore(invalid, store: other); fatalError("Invalid backup accepted") } catch { }
  let otherAfter = try Data(contentsOf: other.url)
  precondition(otherBefore == otherAfter)
  precondition(other.state.snapshotSettings?.intervalMinutes == 45)
  print("PASS: backup round-trip and invalid import leaves disk and memory unchanged")
  // Replace the destination with a directory to force a real atomic-write failure.
  let failureURL = directory.appendingPathComponent("blocked.json")
  let failureStore = try RuleStore(url: failureURL)
  try failureStore.update { $0.cleanupRules = [exact] }
  try FileManager.default.removeItem(at: failureURL)
  try FileManager.default.createDirectory(at: failureURL, withIntermediateDirectories: false)
  let sentinel = failureURL.appendingPathComponent("unchanged")
  try Data("preserve".utf8).write(to: sentinel)
  do {
   try failureStore.update { $0.cleanupRules = [] }
   fatalError("Write failure accepted")
  } catch { }
  precondition(failureStore.state.cleanupRules.count == 1)
  let preservedSentinel = try Data(contentsOf: sentinel)
  precondition(preservedSentinel == Data("preserve".utf8))
  do {
   try ConfigurationBackupService.restore(backup, store: failureStore)
   fatalError("Failed import accepted")
  } catch { }
  precondition(failureStore.state.snapshots.isEmpty)
  precondition(failureStore.state.cleanupRules.count == 1)
  print("PASS: actual write and import failures preserve in-memory rules and existing destination")
  let encodedSnapshot = try JSONEncoder().encode(manual)
  var legacyObject = try JSONSerialization.jsonObject(with: encodedSnapshot) as! [String: Any]
  legacyObject.removeValue(forKey: "cleanupRules")
  legacyObject.removeValue(forKey: "includesCleanupRules")
  let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
  let legacySnapshot = try JSONDecoder().decode(RuleSnapshot.self, from: legacyData)
  precondition(!legacySnapshot.includesCleanupRules)
  try store.update { $0.snapshots = [legacySnapshot]; $0.cleanupRules = [exact] }
  try store.restore(id: legacySnapshot.id)
  precondition(store.state.cleanupRules.count == 1)
  let reloadedLegacy = try RuleStore(url: store.url)
  precondition(!reloadedLegacy.state.snapshots[0].includesCleanupRules)
  print("PASS: legacy snapshot preserves current cleanup rules across decode, save and restore")
  let targetA = DesktopRuleMatcher.Target(uuid: "A", displayUUID: "display", index: 4)
  let targetB = DesktopRuleMatcher.Target(uuid: "B", displayUUID: "display", index: 0)
  var targetRule = exact
  targetRule.targetSpaceUUID = "A"; targetRule.targetDisplayUUID = "display"; targetRule.targetIndex = 0
  precondition(DesktopRuleMatcher.targetIndex(for: targetRule, targets: [targetB, targetA]) == 1)
  precondition(DesktopRuleMatcher.targetIndex(for: targetRule, targets: [targetB]) == nil)
  precondition(DesktopRuleMatcher.targetIndex(for: targetRule, targets: [targetA, targetA]) == nil)
  targetRule.targetDisplayUUID = "other"
  precondition(DesktopRuleMatcher.targetIndex(for: targetRule, targets: [targetA]) == nil)
  targetRule.targetDisplayUUID = "display"; targetRule.targetSpaceUUID = nil
  precondition(DesktopRuleMatcher.targetIndex(for: targetRule, targets: [targetA, targetB]) == 1)
  targetRule.targetIndex = nil
  precondition(DesktopRuleMatcher.targetIndex(for: targetRule, targets: [targetA, targetB]) == nil)
  print("PASS: reordered, missing, duplicate and cross-display targets; explicit legacy index fallback")
 }
}
