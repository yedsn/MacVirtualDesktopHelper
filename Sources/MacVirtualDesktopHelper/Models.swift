import AppKit

struct DesktopSpace: Identifiable {
	let id: UInt64
	let uuid: String
	let displayUUID: String
	let displayIndex: Int
	let index: Int
	let displayCount: Int
	let isCurrent: Bool

	var title: String {
  if id == 0 { return "未知归属".localized }
		if displayCount > 1 {
   return Localization.format("显示器 %d · 桌面 %d", displayIndex + 1, index + 1)
		}
  return Localization.format("桌面 %d", index + 1)
	}

	var shortTitle: String {
		return "\(index + 1)"
	}
}

struct DesktopWindow: Identifiable {
	let id: UInt32
	let ownerName: String
	let title: String
	let bundleID: String
	let pid: pid_t
	let spaceID: UInt64
	let displayUUID: String
	let isOnScreen: Bool
	let isSticky: Bool
	let icon: NSImage?

	var displayTitle: String {
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "（无标题窗口）".localized : trimmed
	}
 var hasKnownSpace: Bool { spaceID != 0 }
 func cleanupCandidate(in windows: [DesktopWindow], isProtected: (DesktopWindow) -> Bool) -> DesktopWindow? {
  guard let live = windows.first(where: { $0.id == id && $0.pid == pid && $0.bundleID == bundleID && $0.title == title }),
   live.hasKnownSpace, !isProtected(live) else { return nil }
  return live
 }
}

struct WindowGroup {
	let space: DesktopSpace
	let windows: [DesktopWindow]
}

struct WindowSnapshot {
	let spaces: [DesktopSpace]
	let groups: [WindowGroup]
	let capturedAt: Date

	var windowCount: Int {
		return Set(groups.flatMap(\.windows).map(\.id)).count
	}
}
