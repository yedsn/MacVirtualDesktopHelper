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
 private var navigationItems: [NSStatusItem] = []
 var settings: () -> ApplicationSettings = { ApplicationSettings() }
 var showSettings: (() -> Void)?
 var showSnapshots: (() -> Void)?
 var showAbout: (() -> Void)?
 private var compactItem: NSStatusItem?
 private var compactView: CompactStatusView?

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
  updateCompact(spaces)
 }

 private func updateCompact(_ spaces: [DesktopSpace]) {
  if compactItem == nil {
   navigationItems.forEach { NSStatusBar.system.removeStatusItem($0) }; navigationItems.removeAll()
   spaceItems.forEach { NSStatusBar.system.removeStatusItem($0.item) }; spaceItems.removeAll()
   if let overviewItem { NSStatusBar.system.removeStatusItem(overviewItem); self.overviewItem = nil }
   let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
   item.autosaveName = "mvdh.compact"
   let view = CompactStatusView()
   view.clickScreenLocation = { NSEvent.mouseLocation }
   view.selectSpace = { [weak self] space in self?.skyLight.setCurrentSpace(displayUUID: space.displayUUID, spaceID: space.id) }
   view.showManager = { [weak self] in
    guard let self else { return }
    if self.settings().windowManager == "system" { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")) } else { self.showOverview() }
   }
   view.showMenu = { [weak self, weak view] event in
    guard let self, let view else { return }
    self.showContextMenu(for: view, event: event)
   }
   item.button?.addSubview(view)
   item.button?.target = self
   item.button?.action = #selector(compactClicked(_:))
   item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
   compactItem = item; compactView = view
  }
  guard let compactView, let compactItem else { return }
  compactView.spaces = spaces
  compactView.navigation = settings().desktopDisplayMode == "navigation"
  compactView.showNameInitial = settings().showDesktopNameInitial == true
  compactView.previousSymbol = settings().previousDesktopSymbol ?? "‹"
  compactView.nextSymbol = settings().nextDesktopSymbol ?? "›"
  compactView.disabledOpacity = CGFloat(settings().disabledIconOpacity ?? 0.35)
  compactView.showNavigationArrows = settings().showNavigationArrows ?? true
  compactView.hideNavigationAtBounds = settings().hideNavigationAtBounds
  compactView.iconSpacing = CGFloat(settings().menuIconSpacing ?? 8)
  let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  let colors = settings().menuColors(dark: dark)
  compactView.foreground = CompactStatusView.color(colors.foreground)
  compactView.symbolForeground = CompactStatusView.color(colors.symbolForeground)
  compactView.background = CompactStatusView.color(colors.background)
  compactView.fontName = settings().menuFontName
  compactView.fontSize = CGFloat(settings().menuFontSize ?? 11)
  compactItem.length = compactView.requiredWidth
  compactView.frame = NSRect(x: 0, y: 0, width: compactView.requiredWidth, height: NSStatusBar.system.thickness)
  compactView.toolTip = "点击编号切换桌面；四方块打开窗口管理；右键打开菜单".localized
 }
 @objc private func compactClicked(_ sender: NSStatusBarButton) {
  guard let event = NSApp.currentEvent, let compactView else { return }
  if event.type == .rightMouseUp { compactView.rightMouseDown(with: event) } else { compactView.mouseDown(with: event) }
 }

	private func rebuildStatusItems(spaces: [DesktopSpace]) {
  navigationItems.forEach { NSStatusBar.system.removeStatusItem($0) }
  navigationItems.removeAll()
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
		overview.button?.image = TrayIconRenderer.manager()
		overview.button?.toolTip = "所有窗口".localized
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
  if settings().desktopDisplayMode == "navigation" {
   for direction in [1, -1] {
    let item = NSStatusBar.system.statusItem(withLength: 28)
    item.button?.title = direction == 1 ? "›" : "‹"
    item.button?.tag = direction
    item.button?.target = self; item.button?.action = #selector(navigate(_:))
    navigationItems.append(item)
   }
  }
	}
 private func updateNavigation(_ spaces: [DesktopSpace]) {
  let navigation = settings().desktopDisplayMode == "navigation"
  for binding in spaceItems { binding.item.isVisible = !navigation || spaces.contains { $0.id == binding.space.id && $0.isCurrent } }
  guard let current = spaces.firstIndex(where: { $0.isCurrent }) else { return }
  for item in navigationItems {
   let destination = current + (item.button?.tag ?? 0)
   let valid = spaces.indices.contains(destination)
   item.button?.isEnabled = valid
   item.isVisible = valid || !settings().hideNavigationAtBounds
  }
 }
 @objc private func navigate(_ sender: NSStatusBarButton) {
  let spaces = skyLight.spaces()
  guard let current = spaces.firstIndex(where: { $0.isCurrent }), spaces.indices.contains(current + sender.tag) else { return }
  let target = spaces[current + sender.tag]
  skyLight.setCurrentSpace(displayUUID: target.displayUUID, spaceID: target.id)
 }

	private func updateCurrentSpaceHighlight(spaces: [DesktopSpace]) {
		for binding in spaceItems {
			let isCurrent = spaces.first(where: { $0.id == binding.space.id })?.isCurrent ?? false
			let number = binding.space.index + 1
			binding.item.button?.title = ""
			binding.item.button?.image = TrayIconRenderer.desktop(number: number, current: isCurrent)
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
  if settings().windowManager == "system" {
   NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
  } else { showOverview() }
	}

	private func showContextMenu(for button: NSView, event: NSEvent? = nil) {
		let menu = NSMenu()
  menu.addItem(withTitle: "规则快照…".localized, action: #selector(openSnapshots), keyEquivalent: "").target = self
  let managerItem = NSMenuItem(title: "窗口管理器".localized, action: nil, keyEquivalent: "")
  let managerMenu = NSMenu()
  let builtIn = managerMenu.addItem(withTitle: "内置所有窗口".localized, action: #selector(openBuiltInManager), keyEquivalent: "")
  builtIn.target = self; builtIn.state = settings().windowManager == "system" ? .off : .on
  let system = managerMenu.addItem(withTitle: "系统 Mission Control".localized, action: #selector(openSystemManager), keyEquivalent: "")
  system.target = self; system.state = settings().windowManager == "system" ? .on : .off
  managerItem.submenu = managerMenu
  menu.addItem(managerItem)
		menu.addItem(NSMenuItem.separator())
  for space in skyLight.spaces() {
   let title = space.title + (space.isCurrent ? "（当前）".localized : "")
   let item = menu.addItem(withTitle: title, action: #selector(openDesktopFromMenu(_:)), keyEquivalent: "")
   item.target = self
   item.representedObject = [space.displayUUID, String(space.id)]
   item.state = space.isCurrent ? .on : .off
  }
  menu.addItem(NSMenuItem.separator())
  menu.addItem(withTitle: "关于 MacVirtualDesktopHelper".localized, action: #selector(openAbout), keyEquivalent: "").target = self
  menu.addItem(withTitle: "设置…".localized, action: #selector(openSettings), keyEquivalent: ",").target = self
  menu.addItem(withTitle: "刷新桌面".localized, action: #selector(refreshFromMenu), keyEquivalent: "").target = self
		menu.addItem(withTitle: "辅助功能权限…".localized, action: #selector(openPermissions), keyEquivalent: "").target = self
		menu.addItem(withTitle: "屏幕录制权限…".localized, action: #selector(openScreenRecording), keyEquivalent: "").target = self
		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: "退出 MacVirtualDesktopHelper".localized, action: #selector(quit), keyEquivalent: "q").target = self
		if let event = event ?? NSApp.currentEvent {
			NSMenu.popUpContextMenu(menu, with: event, for: button)
		} else {
			menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
		}
	}

	@objc private func openOverviewFromMenu() {
		showOverview()
	}
 @objc private func openSnapshots() { showSnapshots?() }
 @objc private func openAbout() { showAbout?() }
 @objc private func openBuiltInManager() { showOverview() }
 @objc private func openSystemManager() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")) }
 @objc private func openDesktopFromMenu(_ sender: NSMenuItem) {
  guard let values = sender.representedObject as? [String], values.count == 2, let id = UInt64(values[1]) else { return }
  skyLight.setCurrentSpace(displayUUID: values[0], spaceID: id)
 }
 @objc private func openSettings() { showSettings?() }

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
