import AppKit

@main struct WindowSnapshotTests {
 static func main() {
 let first = DesktopSpace(id: 10, uuid: "first", displayUUID: "display", displayIndex: 0, index: 0, displayCount: 1, isCurrent: true)
 let second = DesktopSpace(id: 20, uuid: "second", displayUUID: "display", displayIndex: 0, index: 1, displayCount: 1, isCurrent: false)
 let window = DesktopWindow(id: 77, ownerName: "Shared", title: "Document", bundleID: "test.shared", pid: 1, spaceID: 10, displayUUID: "display", isOnScreen: true, isSticky: true, icon: nil)
 let snapshot = WindowSnapshot(spaces: [first, second], groups: [WindowGroup(space: first, windows: [window]), WindowGroup(space: second, windows: [window])], capturedAt: Date())
 precondition(snapshot.windowCount == 1)

 let unknown = DesktopSpace(id: 0, uuid: "unassigned", displayUUID: "", displayIndex: 0, index: -1, displayCount: 0, isCurrent: false)
 precondition(unknown.title == "未知归属")
 print("PASS: shared window count is unique and unknown ownership has an explicit card title")
 }
}
