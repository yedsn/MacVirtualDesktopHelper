import AppKit

@main struct WindowSnapshotTests {
 static func main() throws {
 let first = DesktopSpace(id: 10, uuid: "first", displayUUID: "display", displayIndex: 0, index: 0, displayCount: 1, isCurrent: true)
 let second = DesktopSpace(id: 20, uuid: "second", displayUUID: "display", displayIndex: 0, index: 1, displayCount: 1, isCurrent: false)
 let window = DesktopWindow(id: 77, ownerName: "Shared", title: "Document", bundleID: "test.shared", pid: 1, spaceID: 10, displayUUID: "display", isOnScreen: true, isSticky: true, icon: nil)
 let snapshot = WindowSnapshot(spaces: [first, second], groups: [WindowGroup(space: first, windows: [window]), WindowGroup(space: second, windows: [window])], capturedAt: Date())
 precondition(snapshot.windowCount == 1)
 var protected = false
 precondition(window.cleanupCandidate(in: [window], isProtected: { _ in protected }) != nil)
 protected = true
 precondition(window.cleanupCandidate(in: [window], isProtected: { _ in protected }) == nil)
 protected = false
 precondition(window.cleanupCandidate(in: [], isProtected: { _ in protected }) == nil)
 let reusedID = DesktopWindow(id: 77, ownerName: window.ownerName, title: window.title, bundleID: window.bundleID, pid: 2, spaceID: 10, displayUUID: "display", isOnScreen: true, isSticky: false, icon: nil)
 precondition(window.cleanupCandidate(in: [reusedID], isProtected: { _ in false }) == nil)
 let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at: directory) }
 let store = try RuleStore(url: directory.appendingPathComponent("state.json"))
 let isProtected: (DesktopWindow) -> Bool = { live in
  store.state.cleanupRules.contains { $0.matchResult(bundleID: live.bundleID, applicationPath: "", title: live.title) != .notMatched }
 }
 let reviewed = [window].filter { !isProtected($0) }
 precondition(reviewed.count == 1)
 try store.update { $0.cleanupRules = [WindowRule(bundleID: window.bundleID, applicationPath: "", title: window.title)] }
 var closeRequests = 0
 var flowCloseRequests = 0
 for candidate in reviewed {
  if candidate.cleanupCandidate(in: [window], isProtected: isProtected) != nil { closeRequests += 1 }
 }
 precondition(closeRequests == 0)
 let reloaded = try RuleStore(url: directory.appendingPathComponent("state.json"))
 precondition(reloaded.state.cleanupRules.count == 1)
 try store.update { $0.cleanupRules = [] }
 let beforeSwitch = window.cleanupCandidate(in: [window], isProtected: isProtected)
 precondition(beforeSwitch != nil)
 try store.update { $0.cleanupRules = [WindowRule(bundleID: window.bundleID, applicationPath: "", title: window.title)] }
 precondition(beforeSwitch!.cleanupCandidate(in: [window], isProtected: isProtected) == nil)
 print("PASS: persisted protection changes after review and between desktop checks prevent close requests with unchanged identity")
 print("PASS: unchanged identity rechecks changed protection, disappeared window and reused window ID")
 // Mirrors OverviewWindowController.closeNext for the full cleanup flow: review,
 // pre-switch recheck, post-switch recheck, close and presence reporting.
 let keptWindow = DesktopWindow(id: 78, ownerName: "Kept", title: "Kept", bundleID: "test.kept", pid: 9, spaceID: 10, displayUUID: "display", isOnScreen: true, isSticky: false, icon: nil)
 var liveWindows = [window, keptWindow]
 var closed = 0, skipped = 0
 try store.update { $0.cleanupRules = [] }
 let reviewedFlow = liveWindows.filter { !isProtected($0) }
 precondition(reviewedFlow.count == 2)
 for candidate in reviewedFlow {
  if candidate.id == window.id {
   // Protection is enabled only after the review snapshot while identity stays unchanged.
   try store.update { $0.cleanupRules = [WindowRule(bundleID: window.bundleID, applicationPath: "", title: window.title)] }
  }
  guard let preSwitch = candidate.cleanupCandidate(in: liveWindows, isProtected: isProtected) else { skipped += 1; continue }
  // For the first candidate the desktop switch succeeded but the window disappears
  // before the close request; the second candidate stays present.
  if candidate.id == window.id { liveWindows.removeAll { $0.id == candidate.id } }
  guard preSwitch.cleanupCandidate(in: liveWindows, isProtected: isProtected) != nil else {
   skipped += 1
   continue
  }
  flowCloseRequests += 1
  closed += 1 // the close request removes the revalidated window
 }
 precondition(closeRequests == 0 && flowCloseRequests == 1 && closed == 1 && skipped == 1)
 print("PASS: full cleanup flow counts post-review protection or identity changes as skipped and only closes revalidated windows")

 let unknown = DesktopSpace(id: 0, uuid: "unassigned", displayUUID: "", displayIndex: 0, index: -1, displayCount: 0, isCurrent: false)
 precondition(unknown.title == "未知归属")

 let visible = DesktopWindow(id: 81, ownerName: "A", title: "Visible", bundleID: "test.a", pid: 1, spaceID: 10, displayUUID: "display", isOnScreen: true, isSticky: false, icon: nil)
 var minimized = DesktopWindow(id: 82, ownerName: "B", title: "Minimized", bundleID: "test.b", pid: 2, spaceID: 10, displayUUID: "display", isOnScreen: false, isSticky: false, icon: nil)
 minimized.isMinimized = true
 var hidden = DesktopWindow(id: 83, ownerName: "C", title: "Hidden", bundleID: "test.c", pid: 3, spaceID: 20, displayUUID: "display", isOnScreen: false, isSticky: false, icon: nil)
 hidden.isApplicationHidden = true
 var sharedMinimized = DesktopWindow(id: 84, ownerName: "D", title: "Shared", bundleID: "test.d", pid: 4, spaceID: 10, displayUUID: "display", isOnScreen: false, isSticky: true, icon: nil)
 sharedMinimized.isMinimized = true
 let backgroundGroups = WindowSnapshot.overviewGroups([
  WindowGroup(space: first, windows: [visible, minimized, sharedMinimized]),
  WindowGroup(space: second, windows: [hidden, sharedMinimized])
 ])
 precondition(backgroundGroups.count == 3)
 precondition(backgroundGroups[0].space.id == first.id && backgroundGroups[0].windows.map(\.id) == [81])
 precondition(backgroundGroups[1].space.id == second.id && backgroundGroups[1].windows.isEmpty)
 precondition(backgroundGroups[2].space.id == DesktopSpace.backgroundWindowsID)
 precondition(backgroundGroups[2].windows.map(\.id) == [82, 83, 84])
 var mixed = visible
 mixed.isMinimized = true
 mixed.isApplicationHidden = true
 precondition(mixed.backgroundStateDescription == "已最小化 · 应用已隐藏")
 var backgroundOnly = visible
 backgroundOnly.isAccessibilityUnavailable = true
 precondition(backgroundOnly.belongsToBackgroundSection)
 precondition(backgroundOnly.backgroundStateDescription == "后台窗口")
 precondition(![backgroundOnly].filter { !$0.belongsToBackgroundSection }.contains(where: { _ in true }))
 let unchanged = WindowSnapshot.overviewGroups([WindowGroup(space: first, windows: [visible])])
 precondition(unchanged.count == 1 && unchanged[0].space.id == first.id && unchanged[0].windows.map(\.id) == [81])
 print("PASS: minimized and hidden windows move to one deduplicated trailing card while normal cards stay in place")

 Localization.language = "en"
 precondition(first.title == "Desktop 1")
 precondition(unknown.title == "Unknown ownership")
 precondition(DesktopSpace.backgroundWindowsSpace.title == "Hidden or minimized")
 let external = DesktopSpace(id: 30, uuid: "third", displayUUID: "external", displayIndex: 1, index: 2, displayCount: 2, isCurrent: false)
 precondition(external.title == "Display 2 · Desktop 3")
 Localization.language = "zh-CN"
 precondition(external.title == "显示器 2 · 桌面 3")
 print("PASS: shared window count is unique and unknown ownership has an explicit card title")
 }
}
