import AppKit

@main struct WindowSnapshotTests {
 static func main() {
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
 print("PASS: unchanged identity rechecks changed protection, disappeared window and reused window ID")

 let unknown = DesktopSpace(id: 0, uuid: "unassigned", displayUUID: "", displayIndex: 0, index: -1, displayCount: 0, isCurrent: false)
 precondition(unknown.title == "未知归属")
 Localization.language = "en"
 precondition(first.title == "Desktop 1")
 precondition(unknown.title == "Unknown ownership")
 let external = DesktopSpace(id: 30, uuid: "third", displayUUID: "external", displayIndex: 1, index: 2, displayCount: 2, isCurrent: false)
 precondition(external.title == "Display 2 · Desktop 3")
 Localization.language = "zh-CN"
 precondition(external.title == "显示器 2 · 桌面 3")
 print("PASS: shared window count is unique and unknown ownership has an explicit card title")
 }
}
