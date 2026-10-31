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
		if displayCount > 1 {
			return "显示器 \(displayIndex + 1) · 桌面 \(index + 1)"
		}
		return "桌面 \(index + 1)"
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
		return trimmed.isEmpty ? "（无标题窗口）" : trimmed
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
		return groups.reduce(0) { $0 + $1.windows.count }
	}
}
