import AppKit

@main struct DesktopOverlayTests {
 static func main() {
  let first = DesktopSpace(id: 1, uuid: "one", displayUUID: "DISPLAY-A", displayIndex: 0, index: 1, displayCount: 2, isCurrent: true)
  let second = DesktopSpace(id: 2, uuid: "two", displayUUID: "DISPLAY-B", displayIndex: 1, index: 4, displayCount: 2, isCurrent: true)
  precondition(DesktopOverlay.title(displayUUID: "display-a", spaces: [first, second]) == first.title)
  precondition(DesktopOverlay.title(displayUUID: "DISPLAY-B", spaces: [first, second]) == second.title)
  precondition(DesktopOverlay.title(displayUUID: "unknown", spaces: [first, second]) == nil)
  precondition(DesktopOverlay.title(displayUUID: "shared-display", spaces: [first]) == first.title)
  precondition(DesktopOverlay.title(displayUUID: "unknown", spaces: []) == nil)
  print("PASS: per-display overlay titles, case-insensitive UUID, shared Space and missing display")
 }
}
