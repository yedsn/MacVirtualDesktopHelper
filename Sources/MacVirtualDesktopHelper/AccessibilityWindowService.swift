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

	func focus(_ target: DesktopWindow) -> String? {
		guard isTrusted else {
			return "需要先授予辅助功能权限。".localized
		}
		guard let app = NSRunningApplication(processIdentifier: target.pid) else {
			return "应用已经退出。"
		}
		guard let axWindow = accessibilityWindow(windowID: target.id, pid: target.pid) else {
			return "当前无法读取该窗口的辅助功能对象。".localized
		}

		_ = app.activate(options: [.activateAllWindows])
		let result = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
		let focusResult = AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
		if result != .success && focusResult != .success {
			return "窗口激活失败（AX 错误 \(result.rawValue)）。"
		}
		return nil
	}

	func containsWindow(_ target: DesktopWindow) -> Bool {
		return accessibilityWindow(windowID: target.id, pid: target.pid) != nil
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
