import AppKit

final class StatusBarController: NSObject {
	private struct SpaceItemBinding {
		let space: DesktopSpace
		let item: NSStatusItem
	}

	private let skyLight: SkyLightService
	private let showOverview: () -> Void
	private var overviewItem: NSStatusItem?
	private var spaceItems: [SpaceItemBinding] = []
	private var lastSignature = ""
	private var refreshTimer: Timer?

	init(skyLight: SkyLightService, showOverview: @escaping () -> Void) {
		self.skyLight = skyLight
		self.showOverview = showOverview
		super.init()
	}

	func start() {
		NSWorkspace.shared.notificationCenter.addObserver(
			self,
			selector: #selector(spaceDidChange),
			name: NSWorkspace.activeSpaceDidChangeNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(screenConfigurationDidChange),
			name: NSApplication.didChangeScreenParametersNotification,
			object: nil
		)
		NSWorkspace.shared.notificationCenter.addObserver(
			self,
			selector: #selector(activeApplicationDidChange),
			name: NSWorkspace.didActivateApplicationNotification,
			object: nil
		)

		let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(spaceDidChange), userInfo: nil, repeats: true)
		timer.tolerance = 0.25
		RunLoop.main.add(timer, forMode: .common)
		refreshTimer = timer
		refresh(forceRebuild: true)
	}

	func refresh(forceRebuild: Bool = false) {
		let spaces = skyLight.spaces()
		guard !spaces.isEmpty else { return }
		let signature = spaces.map { "\($0.displayUUID):\($0.uuid)" }.joined(separator: "|")
		if forceRebuild || signature != lastSignature {
			rebuildStatusItems(spaces: spaces)
			lastSignature = signature
		}
		updateCurrentSpaceHighlight(spaces: spaces)
		if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
			let lines = spaceItems.map { "id=\($0.space.id) visible=\($0.item.isVisible) frame=\(String(describing: $0.item.button?.window?.frame))" }
			try? lines.joined(separator: " | ").write(toFile: "/tmp/wvdh-status-diagnostics.txt", atomically: true, encoding: .utf8)
		}
	}

	private func rebuildStatusItems(spaces: [DesktopSpace]) {
		if let overviewItem {
			NSStatusBar.system.removeStatusItem(overviewItem)
		}
		for binding in spaceItems {
			NSStatusBar.system.removeStatusItem(binding.item)
		}
		spaceItems.removeAll()

		// NSStatusBar inserts each newly created item to the left of earlier items.
		// Creating the overview first and spaces in reverse produces left-to-right
		// desktop order followed by the overview control.
		let overview = NSStatusBar.system.statusItem(withLength: 32)
		overview.autosaveName = "mvdh.overview"
		overview.behavior = []
		overview.isVisible = true
		if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "所有窗口") {
			image.isTemplate = true
			overview.button?.image = image
		} else {
			overview.button?.title = "▦"
		}
		overview.button?.toolTip = "所有窗口"
		overview.button?.target = self
		overview.button?.action = #selector(overviewClicked(_:))
		overview.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
		overviewItem = overview

		for space in spaces.reversed() {
			let item = NSStatusBar.system.statusItem(withLength: 32)
			item.autosaveName = "mvdh.\(space.displayUUID).\(space.uuid)"
			item.behavior = []
			item.isVisible = true
			item.button?.target = self
			item.button?.action = #selector(desktopClicked(_:))
			item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
			item.button?.toolTip = space.title
			spaceItems.append(SpaceItemBinding(space: space, item: item))
		}
	}

	private func updateCurrentSpaceHighlight(spaces: [DesktopSpace]) {
		for binding in spaceItems {
			let isCurrent = spaces.first(where: { $0.id == binding.space.id })?.isCurrent ?? false
			let number = binding.space.index + 1
			let text = isCurrent ? "●\(number)" : " \(number)"
			let font = NSFont.monospacedDigitSystemFont(
				ofSize: 13,
				weight: isCurrent ? .bold : .medium
			)
			let color = isCurrent ? NSColor.controlAccentColor : NSColor.labelColor
			binding.item.button?.attributedTitle = NSAttributedString(
				string: text,
				attributes: [.font: font, .foregroundColor: color]
			)
			binding.item.button?.toolTip = isCurrent ? "\(binding.space.title)（当前）" : binding.space.title
			binding.item.button?.setAccessibilityLabel(isCurrent ? "\(binding.space.title)，当前" : binding.space.title)
		}
	}

	@objc private func desktopClicked(_ sender: NSStatusBarButton) {
		guard let binding = spaceItems.first(where: { $0.item.button === sender }) else { return }
		if NSApp.currentEvent?.type == .rightMouseUp {
			showContextMenu(for: sender)
			return
		}

		skyLight.setCurrentSpace(displayUUID: binding.space.displayUUID, spaceID: binding.space.id)
		for delay in [0.12, 0.45, 0.9] {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
				self?.refresh()
			}
		}
	}

	@objc private func overviewClicked(_ sender: NSStatusBarButton) {
		if NSApp.currentEvent?.type == .rightMouseUp {
			showContextMenu(for: sender)
			return
		}
		showOverview()
	}

	private func showContextMenu(for button: NSStatusBarButton) {
		let menu = NSMenu()
		menu.addItem(withTitle: "所有窗口…", action: #selector(openOverviewFromMenu), keyEquivalent: "").target = self
		menu.addItem(withTitle: "刷新桌面", action: #selector(refreshFromMenu), keyEquivalent: "").target = self
		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: "辅助功能权限…", action: #selector(openPermissions), keyEquivalent: "").target = self
		menu.addItem(withTitle: "屏幕录制权限…", action: #selector(openScreenRecording), keyEquivalent: "").target = self
		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: "退出 MacVirtualDesktopHelper", action: #selector(quit), keyEquivalent: "q").target = self
		if let event = NSApp.currentEvent {
			NSMenu.popUpContextMenu(menu, with: event, for: button)
		} else {
			menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
		}
	}

	@objc private func openOverviewFromMenu() {
		showOverview()
	}

	@objc private func refreshFromMenu() {
		refresh(forceRebuild: true)
	}

	@objc private func openPermissions() {
		AccessibilityWindowService().openAccessibilitySettings()
	}

	@objc private func openScreenRecording() {
		CGRequestScreenCaptureAccess()
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
			NSWorkspace.shared.open(url)
		}
	}

	@objc private func quit() {
		NSApp.terminate(nil)
	}

	@objc private func spaceDidChange() {
		refresh()
	}

	@objc private func screenConfigurationDidChange() {
		refresh(forceRebuild: true)
	}

	@objc private func activeApplicationDidChange() {
		refresh()
	}

	deinit {
		refreshTimer?.invalidate()
		NSWorkspace.shared.notificationCenter.removeObserver(self)
		NotificationCenter.default.removeObserver(self)
	}
}
