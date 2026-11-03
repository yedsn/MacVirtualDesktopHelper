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
		if id == Self.otherWindowsID { return "其他窗口".localized }
		if displayCount > 1 {
			return Localization.format("显示器 %d · 桌面 %d", displayIndex + 1, index + 1)
		}
		return Localization.format("桌面 %d", index + 1)
	}

	var shortTitle: String {
		return "\(index + 1)"
	}

	static let otherWindowsID = UInt64.max - 1
	static var otherWindowsSpace: DesktopSpace {
		DesktopSpace(id: otherWindowsID, uuid: "other-windows", displayUUID: "", displayIndex: 0, index: -1, displayCount: 0, isCurrent: false)
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
	var isMinimizedStateKnown = true
	var isApplicationHidden = false
	/// This capture could not resolve an Accessibility object; not proof of hiding or closure.
	var isAccessibilityUnavailable = false
	var isExcludedFromSwitcher = false
	/// A normal application window on an inactive Space can be absent from AX
	/// until that Space is selected. Keep it on its desktop in the overview.
	var awaitsDesktopActivation = false

	var displayTitle: String {
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "（无标题窗口）".localized : trimmed
	}
 var hasKnownSpace: Bool { spaceID != 0 }
	var belongsToBackgroundSection: Bool { isMinimized || isApplicationHidden }
	var isOverviewDesktopCandidate: Bool {
		hasKnownSpace && (awaitsDesktopActivation || (!isExcludedFromSwitcher && !isAccessibilityUnavailable))
	}
	var isEligibleForBulkOperations: Bool { hasKnownSpace && !isExcludedFromSwitcher && !belongsToBackgroundSection && !isAccessibilityUnavailable && isMinimizedStateKnown }
	// SkyLight rule moves also support inactive desktops and hidden/minimized windows.
	// Keep rule recording and application independent of AX bulk-operation access.
	var isDesktopRuleCandidate: Bool { isOverviewDesktopCandidate && !isSticky }
	var backgroundStateDescription: String {
		[isMinimized ? "已最小化".localized : nil, isApplicationHidden ? "应用已隐藏".localized : nil]
			.compactMap { $0 }.joined(separator: " · ")
	}
 func cleanupCandidate(in windows: [DesktopWindow], requiresOperationAccess: Bool = true, isProtected: (DesktopWindow) -> Bool) -> DesktopWindow? {
  guard let live = windows.first(where: { $0.id == id && $0.pid == pid && $0.bundleID == bundleID && $0.title == title }),
   live.isOverviewDesktopCandidate, live.spaceID == spaceID, live.isSticky == isSticky, !isProtected(live) else { return nil }
  if requiresOperationAccess && (live.isExcludedFromSwitcher || live.isAccessibilityUnavailable || !live.isMinimizedStateKnown) { return nil }
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
	var switcherIdentities: [UInt32: AXUIElement] = [:]

	var windowCount: Int {
		return Set(groups.flatMap(\.windows).map(\.id)).count
	}

	/// Desktop cards share the switcher's candidates; all excluded application
	/// windows remain discoverable in one final, deduplicated section.
	static func overviewGroups(_ groups: [WindowGroup]) -> [WindowGroup] {
		var other: [UInt32: DesktopWindow] = [:]
		var regular: [WindowGroup] = []
		for group in groups {
			var candidates: [DesktopWindow] = []
			for window in group.windows {
				if !window.isOverviewDesktopCandidate {
					other[window.id] = window
				} else { candidates.append(window) }
			}
			if group.space.id != 0 && group.space.id != DesktopSpace.otherWindowsID {
				regular.append(WindowGroup(space: group.space, windows: candidates))
			}
		}
		let windows = other.values.sorted {
			let owner = $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName)
			if owner != .orderedSame { return owner == .orderedAscending }
			let title = $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle)
			return title == .orderedSame ? $0.id < $1.id : title == .orderedAscending
		}
		return regular + (windows.isEmpty ? [] : [WindowGroup(space: .otherWindowsSpace, windows: windows)])
	}
}
