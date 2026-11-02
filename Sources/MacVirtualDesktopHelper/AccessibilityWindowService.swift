import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

final class AccessibilityWindowService {
	private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
	private let getWindow: GetWindowFunction?

	init() {
		if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") {
			getWindow = unsafeBitCast(symbol, to: GetWindowFunction.self)
		} else {
			getWindow = nil
		}
	}

	var isTrusted: Bool {
		return AXIsProcessTrusted()
	}

	@discardableResult
	func requestAccess() -> Bool {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		return AXIsProcessTrustedWithOptions(options)
	}

	func openAccessibilitySettings() {
		let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
		NSWorkspace.shared.open(url)
	}

	func focus(_ target: DesktopWindow, activateAllWindows: Bool = true, expectedWindow: AXUIElement? = nil) -> String? {
		guard isTrusted else {
			return "需要先授予辅助功能权限。".localized
		}
		guard let app = NSRunningApplication(processIdentifier: target.pid) else {
			return "应用已经退出。"
		}
		guard let axWindow = accessibilityWindow(windowID: target.id, pid: target.pid) else {
			return "当前无法读取该窗口的辅助功能对象。".localized
		}
		if let expectedWindow, !CFEqual(expectedWindow, axWindow) {
			return "目标窗口身份已改变。"
		}

		if app.isHidden { app.unhide() }
		// Activate only the target process without asking AppKit to raise every
		// window owned by the application. The target AX window is raised below.
		_ = app.activate(options: activateAllWindows ? [.activateAllWindows] : [])
		let application = AXUIElementCreateApplication(target.pid)
		AXUIElementSetMessagingTimeout(application, 1.5)
		_ = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
		// A minimized AX window can be raised without becoming visible on some
		// apps, so restore it before asking for focus.
		let restoreResult = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
		let result = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
		let focusResult = AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
		if result != .success && focusResult != .success && restoreResult != .success {
			return "窗口激活失败（AX 错误 \(result.rawValue)）。"
		}
		return nil
	}

	func containsWindow(_ target: DesktopWindow) -> Bool {
		return accessibilityWindow(windowID: target.id, pid: target.pid) != nil
	}
	func windowIdentity(_ target: DesktopWindow) -> AXUIElement? {
		accessibilityWindow(windowID: target.id, pid: target.pid)
	}
	func windowTitle(windowID: CGWindowID, pid: pid_t) -> String? {
		guard isTrusted, let window = accessibilityWindow(windowID: windowID, pid: pid) else { return nil }
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
		return value as? String
	}
	func isStandardWindow(_ target: DesktopWindow) -> Bool {
		guard let window = accessibilityWindow(windowID: target.id, pid: target.pid) else { return false }
		var role: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
			role as? String == kAXWindowRole as String else { return false }
		var subrole: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success else { return true }
		return [kAXStandardWindowSubrole as String, kAXDialogSubrole as String, kAXSystemDialogSubrole as String].contains(subrole as? String ?? "")
	}

	func isMinimized(_ target: DesktopWindow) -> Bool? {
		guard let window = accessibilityWindow(windowID: target.id, pid: target.pid) else { return nil }
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
			let value else { return nil }
		return (value as? NSNumber)?.boolValue
	}

 // nil means the application could not be inspected, never proof of closure.
 func windowPresence(_ target: DesktopWindow) -> Bool? {
  guard NSRunningApplication(processIdentifier: target.pid) != nil else { return false }
  guard isTrusted, let getWindow else { return nil }
  let application = AXUIElementCreateApplication(target.pid)
  AXUIElementSetMessagingTimeout(application, 1.5)
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
   let windows = value as? [AXUIElement] else { return nil }
  var unresolved = false
  for window in windows {
   var id: CGWindowID = 0
   guard getWindow(window, &id) == .success else { unresolved = true; continue }
   if id == target.id { return true }
  }
  return unresolved ? nil : false
 }

 func focusedWindowID(pid: pid_t) -> CGWindowID? {
  guard isTrusted, let getWindow else { return nil }
  let app = AXUIElementCreateApplication(pid)
  AXUIElementSetMessagingTimeout(app, 0.3)
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
   let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
  let window = unsafeBitCast(value, to: AXUIElement.self)
  var id: CGWindowID = 0
  return getWindow(window, &id) == .success ? id : nil
 }

	struct WindowDetails {
		let title: String?
		let isMinimized: Bool?
		let isStandard: Bool?
	}

	struct WindowInspection {
		let windows: [CGWindowID: WindowDetails]
		let error: AXError?
		let hasUnresolvedIDs: Bool

		func presence(of id: CGWindowID) -> Bool? {
			if windows[id] != nil { return true }
			return error != nil || hasUnresolvedIDs ? nil : false
		}

		func awaitsDesktopActivation(_ id: CGWindowID, isRegularApplication: Bool, isOnCurrentSpace: Bool) -> Bool {
			// AXWindows commonly covers only the selected Space. Its absence is not
			// a reason to move another desktop's ordinary app window into Other.
			isRegularApplication && !isOnCurrentSpace && windows[id]?.isStandard != false
		}

		func apply(to window: inout DesktopWindow) {
			let details = windows[window.id]
			window.isAccessibilityUnavailable = details == nil
			window.isMinimizedStateKnown = details?.isMinimized != nil
			window.isMinimized = details?.isMinimized == true
		}
	}

	/// One bounded application-level query per capture. Missing objects and failed
	/// attributes carry no evidence that an off-desktop window is hidden or closed.
	func inspectWindows(pid: pid_t) -> WindowInspection {
		guard isTrusted, let getWindow else {
			return WindowInspection(windows: [:], error: .apiDisabled, hasUnresolvedIDs: false)
		}
		let application = AXUIElementCreateApplication(pid)
		AXUIElementSetMessagingTimeout(application, 0.3)
		var value: CFTypeRef?
		let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
		guard result == .success, let windows = value as? [AXUIElement] else {
			return WindowInspection(windows: [:], error: result == .success ? .failure : result, hasUnresolvedIDs: false)
		}
		var details: [CGWindowID: WindowDetails] = [:]
		var unresolved = false
		let deadline = Date().addingTimeInterval(0.8)
		for window in windows {
			guard Date() < deadline else {
				return WindowInspection(windows: details, error: .cannotComplete, hasUnresolvedIDs: true)
			}
			AXUIElementSetMessagingTimeout(window, 0.1)
			var id: CGWindowID = 0
			guard getWindow(window, &id) == .success else { unresolved = true; continue }
			func attribute(_ name: CFString) -> CFTypeRef? {
				var value: CFTypeRef?
				return AXUIElementCopyAttributeValue(window, name, &value) == .success ? value : nil
			}
			let title = attribute(kAXTitleAttribute as CFString) as? String
			let minimized = (attribute(kAXMinimizedAttribute as CFString) as? NSNumber)?.boolValue
			let role = attribute(kAXRoleAttribute as CFString) as? String
			let subrole = attribute(kAXSubroleAttribute as CFString) as? String
			let standard = role.map { role in
				role == kAXWindowRole as String && (subrole == nil || [kAXStandardWindowSubrole as String, kAXDialogSubrole as String, kAXSystemDialogSubrole as String].contains(subrole!))
			}
			details[id] = WindowDetails(title: title, isMinimized: minimized, isStandard: standard)
		}
		return WindowInspection(windows: details, error: nil, hasUnresolvedIDs: unresolved)
	}

	func close(_ target: DesktopWindow) -> String? {
		guard isTrusted else { return "需要先授予辅助功能权限。".localized }
		guard let window = accessibilityWindow(windowID: target.id, pid: target.pid) else {
			return "当前无法读取该窗口的辅助功能对象。".localized
		}
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success,
			let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return "该窗口未提供关闭按钮。".localized }
		let button = unsafeBitCast(value, to: AXUIElement.self)
		let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
		return result == .success ? nil : "关闭请求失败（AX 错误 \(result.rawValue)）。"
	}

	private func accessibilityWindow(windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
		guard let getWindow else { return nil }
		let application = AXUIElementCreateApplication(pid)
		AXUIElementSetMessagingTimeout(application, 1.5)
		var rawWindows: CFTypeRef?
		guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawWindows) == .success,
			let windows = rawWindows as? [AXUIElement] else {
			return nil
		}

		for window in windows {
			var candidateID: CGWindowID = 0
			guard getWindow(window, &candidateID) == .success else { continue }
			if candidateID == windowID {
				return window
			}
		}
		return nil
	}
}
