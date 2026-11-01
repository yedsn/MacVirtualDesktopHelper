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
		if id == Self.backgroundWindowsID { return "隐藏或最小化".localized }
		if displayCount > 1 {
			return Localization.format("显示器 %d · 桌面 %d", displayIndex + 1, index + 1)
		}
		return Localization.format("桌面 %d", index + 1)
	}

	var shortTitle: String {
		return "\(index + 1)"
	}

	static let backgroundWindowsID = UInt64.max
	static var backgroundWindowsSpace: DesktopSpace {
		DesktopSpace(id: backgroundWindowsID, uuid: "background-windows", displayUUID: "", displayIndex: 0, index: -1, displayCount: 0, isCurrent: false)
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
	var isMinimized = false
	var isApplicationHidden = false

	var displayTitle: String {
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "（无标题窗口）".localized : trimmed
	}
 var hasKnownSpace: Bool { spaceID != 0 }
	var belongsToBackgroundSection: Bool { isMinimized || isApplicationHidden }
	var backgroundStateDescription: String {
		[isMinimized ? "已最小化".localized : nil, isApplicationHidden ? "应用已隐藏".localized : nil]
			.compactMap { $0 }.joined(separator: " · ")
	}
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

	/// Keeps hidden and minimized windows discoverable without duplicating them
	/// inside their owning desktop cards.
	static func overviewGroups(_ groups: [WindowGroup]) -> [WindowGroup] {
		var background: [UInt32: DesktopWindow] = [:]
		var regular: [WindowGroup] = []
		for group in groups where group.space.id != DesktopSpace.backgroundWindowsID {
			var visible: [DesktopWindow] = []
			for window in group.windows {
				if window.belongsToBackgroundSection { background[window.id] = window }
				else { visible.append(window) }
			}
			regular.append(WindowGroup(space: group.space, windows: visible))
		}
		guard !background.isEmpty else { return regular }
		let windows = background.values.sorted {
			if $0.ownerName.caseInsensitiveCompare($1.ownerName) != .orderedSame {
				return $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending
			}
			return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
		}
		return regular + [WindowGroup(space: .backgroundWindowsSpace, windows: windows)]
	}
}
