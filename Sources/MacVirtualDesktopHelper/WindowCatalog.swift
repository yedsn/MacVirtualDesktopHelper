import AppKit
import CoreGraphics

final class WindowCatalog {
	private let skyLight: SkyLightService
	private let systemBundleIdentifiers: Set<String> = [
		"com.apple.dock",
		"com.apple.controlcenter",
		"com.apple.notificationcenterui",
		"com.apple.systemuiserver",
		"com.apple.WindowServer",
		"com.apple.Spotlight",
		"com.apple.wallpaper.agent",
		"com.apple.CoreServicesUIAgent"
	]
	private let systemOwnerNames: Set<String> = [
		"Window Server",
		"Dock",
		"程序坞",
		"Control Center",
		"控制中心",
		"Notification Center",
		"通知中心",
		"Spotlight",
		"聚焦",
		"Wallpaper",
		"墙纸",
		"SystemUIServer",
		"CursorUIViewService",
		"自动填充",
		"辅助功能"
	]

	init(skyLight: SkyLightService) {
		self.skyLight = skyLight
	}

	func snapshot() -> WindowSnapshot {
		let spaces = skyLight.spaces()
		let currentSpaceID = spaces.first(where: { $0.isCurrent })?.id
		let spaceIDs = Set(spaces.map(\.id))
		let windowInfo = cgWindowInfo()
		let currentPID = ProcessInfo.processInfo.processIdentifier
		var seenWindowIDs = Set<CGWindowID>()
		var windowsBySpace: [UInt64: [DesktopWindow]] = [:]

		for space in spaces {
			for windowID in skyLight.windowIDs(on: space.id) where !seenWindowIDs.contains(windowID) {
				guard let info = windowInfo[windowID] else { continue }
				guard shouldInclude(info: info, currentPID: currentPID) else { continue }

				let associatedSpaceIDs = skyLight.spaceIDs(for: windowID).filter { spaceIDs.contains($0) }
				guard !associatedSpaceIDs.isEmpty else { continue }
				let isSticky = associatedSpaceIDs.count > 1
				let targetSpaceID: UInt64
				if isSticky {
					targetSpaceID = currentSpaceID.flatMap { associatedSpaceIDs.contains($0) ? $0 : nil }
						?? associatedSpaceIDs.first!
				} else {
					targetSpaceID = associatedSpaceIDs[0]
				}

				guard let targetSpace = spaces.first(where: { $0.id == targetSpaceID }) else { continue }
				seenWindowIDs.insert(windowID)

				let pid = int32Value(info[kCGWindowOwnerPID as String]) ?? 0
				let app = NSRunningApplication(processIdentifier: pid)
				let ownerName = stringValue(info[kCGWindowOwnerName as String])
					?? app?.localizedName
					?? "未知应用"
				let window = DesktopWindow(
					id: windowID,
					ownerName: ownerName,
					title: stringValue(info[kCGWindowName as String]) ?? "",
					bundleID: app?.bundleIdentifier ?? "",
					pid: pid,
					spaceID: targetSpaceID,
					displayUUID: targetSpace.displayUUID,
					isOnScreen: boolValue(info[kCGWindowIsOnscreen as String]) ?? false,
					isSticky: isSticky,
					icon: app?.icon
				)
				windowsBySpace[targetSpaceID, default: []].append(window)
			}
		}

		let groups = spaces.map { space in
			let windows = (windowsBySpace[space.id] ?? []).sorted {
				if $0.ownerName.caseInsensitiveCompare($1.ownerName) != .orderedSame {
					return $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending
				}
				return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
			}
			return WindowGroup(space: space, windows: windows)
		}

		return WindowSnapshot(spaces: spaces, groups: groups, capturedAt: Date())
	}

	func currentSpaceIDsByDisplay() -> [String: UInt64] {
		var result: [String: UInt64] = [:]
		for space in skyLight.spaces() where space.isCurrent {
			result[space.displayUUID] = space.id
		}
		return result
	}

	private func cgWindowInfo() -> [CGWindowID: [String: Any]] {
		let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
		var result: [CGWindowID: [String: Any]] = [:]
		for info in raw {
			guard let windowID = uint32Value(info[kCGWindowNumber as String]) else { continue }
			result[windowID] = info
		}
		return result
	}

	private func shouldInclude(info: [String: Any], currentPID: pid_t) -> Bool {
		guard intValue(info[kCGWindowLayer as String]) == 0 else { return false }
		guard let pid = int32Value(info[kCGWindowOwnerPID as String]), pid > 0, pid != currentPID else { return false }
		guard let alpha = doubleValue(info[kCGWindowAlpha as String]), alpha > 0.01 else { return false }
		let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
		let width = doubleValue(bounds["Width"]) ?? 0
		let height = doubleValue(bounds["Height"]) ?? 0
		guard width >= 80, height >= 40 else { return false }

		let app = NSRunningApplication(processIdentifier: pid)
		let ownerName = stringValue(info[kCGWindowOwnerName as String]) ?? app?.localizedName ?? ""
		let windowTitle = stringValue(info[kCGWindowName as String]) ?? ""
		if systemOwnerNames.contains(ownerName) { return false }
		if let bundleID = app?.bundleIdentifier, systemBundleIdentifiers.contains(bundleID) { return false }
		if windowTitle.isEmpty && app?.activationPolicy != .regular { return false }
		return true
	}

	private func stringValue(_ value: Any?) -> String? {
		if let string = value as? String { return string }
		if let number = value as? NSNumber { return number.stringValue }
		return nil
	}

	private func intValue(_ value: Any?) -> Int? {
		if let number = value as? NSNumber { return number.intValue }
		if let value = value as? Int { return value }
		return nil
	}

	private func int32Value(_ value: Any?) -> Int32? {
		if let number = value as? NSNumber { return number.int32Value }
		if let value = value as? Int32 { return value }
		if let value = value as? Int { return Int32(clamping: value) }
		return nil
	}

	private func uint32Value(_ value: Any?) -> UInt32? {
		if let number = value as? NSNumber { return number.uint32Value }
		if let value = value as? UInt32 { return value }
		if let value = value as? Int { return UInt32(clamping: value) }
		return nil
	}

	private func doubleValue(_ value: Any?) -> Double? {
		if let number = value as? NSNumber { return number.doubleValue }
		if let value = value as? Double { return value }
		if let value = value as? Int { return Double(value) }
		return nil
	}

	private func boolValue(_ value: Any?) -> Bool? {
		if let value = value as? Bool { return value }
		if let number = value as? NSNumber { return number.boolValue }
		return nil
	}
}
