import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var skyLight: SkyLightService?
	private var statusBarController: StatusBarController?
	private var overviewController: OverviewWindowController?
 private let hotKeys = GlobalHotKeys()
 private let desktopOverlay = DesktopOverlay()
 private var previousSpaceID: UInt64?
 private var currentSpaceID: UInt64?
 private var currentSpacesByDisplay: [String: UInt64] = [:]
 private var focusTimer: Timer?
 private var lastWindows: [UInt64: DesktopWindow] = [:]
 private let accessibility = AccessibilityWindowService()
 private var logDocument: TextDocumentController?
 private var licenseDocument: TextDocumentController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		installMainMenu()
  ApplicationLog.write("Application started")
  DistributedNotificationCenter.default().addObserver(self, selector: #selector(showOverview), name: Notification.Name("local.macvirtualdesktophelper.showOverview"), object: nil)
  NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

		do {
			let skyLight = try SkyLightService()
			let catalog = WindowCatalog(skyLight: skyLight)
			let accessibility = AccessibilityWindowService()
			let overview = OverviewWindowController(
				skyLight: skyLight,
				catalog: catalog,
				accessibility: accessibility
			)
			self.skyLight = skyLight
			overviewController = overview

			let statusBar = StatusBarController(skyLight: skyLight) { [weak overview] in
				overview?.show()
			}
			statusBarController = statusBar
   statusBar.settings = { [weak overview] in overview?.applicationSettings ?? ApplicationSettings() }
   statusBar.showSettings = { [weak overview] in overview?.showSettings() }
   statusBar.showSnapshots = { [weak overview] in overview?.showSnapshots() }
   statusBar.showAbout = { [weak self] in self?.showAbout() }
   statusBar.showSupport = { [weak self] in self?.openDonate() }
   overview.settingsChanged = { [weak self, weak statusBar] in statusBar?.refresh(forceRebuild: true); self?.reloadHotKeys(); self?.spaceChanged() }
   hotKeys.perform = { [weak self] action in self?.performHotKey(action) }
   reloadHotKeys()
   spaceChanged()
   desktopOverlay.showStartup(settings: overview.applicationSettings)
			statusBar.start()
   let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.rememberFocusedWindow() }
   timer.tolerance = 0.15
   RunLoop.main.add(timer, forMode: .common)
   focusTimer = timer

			if ProcessInfo.processInfo.arguments.contains("--show-overview") {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak overview] in
					overview?.show()
				}
			}
		} catch {
			let alert = NSAlert()
			alert.alertStyle = .critical
			alert.messageText = "无法启动 MacVirtualDesktopHelper".localized
			alert.informativeText = error.localizedDescription
			alert.addButton(withTitle: "退出".localized)
			alert.runModal()
			NSApp.terminate(nil)
		}
	}

 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  overviewController?.show()
  return true
 }

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return false
	}

	private func installMainMenu() {
		let mainMenu = NSMenu()
		let appMenuItem = NSMenuItem()
		mainMenu.addItem(appMenuItem)
		let appMenu = NSMenu()
		appMenuItem.submenu = appMenu
  appMenu.addItem(withTitle: "设置…".localized, action: #selector(openSettings), keyEquivalent: ",").target = self
  appMenu.addItem(withTitle: "查看日志…".localized, action: #selector(openLog), keyEquivalent: "").target = self
  appMenu.addItem(withTitle: "开源许可…".localized, action: #selector(openLicense), keyEquivalent: "").target = self
  appMenu.addItem(withTitle: "支持原作者…".localized, action: #selector(openDonate), keyEquivalent: "").target = self
		appMenu.addItem(withTitle: "关于 MacVirtualDesktopHelper".localized, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
		appMenu.addItem(NSMenuItem.separator())
		let hideItem = appMenu.addItem(withTitle: "隐藏".localized, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		hideItem.target = NSApp
		appMenu.addItem(NSMenuItem.separator())
		let quitItem = appMenu.addItem(withTitle: "退出".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		quitItem.target = NSApp
		NSApp.mainMenu = mainMenu
	}
 @objc private func openSettings() { overviewController?.showSettings() }
 @objc private func openLog() {
  do {
   let contents = try String(contentsOf: ApplicationLog.url, encoding: .utf8)
   if logDocument == nil { logDocument = TextDocumentController(title: "应用日志".localized) }
   logDocument?.show(contents: contents)
  } catch { NSAlert(error: error).runModal() }
 }
 @objc private func openLicense() {
  guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "md") else {
   let alert = NSAlert(); alert.messageText = "应用包内缺少许可文件".localized; alert.informativeText = "请重新构建或安装完整应用。".localized; alert.runModal(); return
  }
  do {
   var contents = try String(contentsOf: url, encoding: .utf8)
   if let upstream = Bundle.main.url(forResource: "YABAI-LICENSE", withExtension: "txt") {
    contents += "\n\nYABAI-LICENSE.txt\n\n" + (try String(contentsOf: upstream, encoding: .utf8))
   }
   if licenseDocument == nil { licenseDocument = TextDocumentController(title: "开源许可".localized) }
   licenseDocument?.show(contents: contents)
  } catch { NSAlert(error: error).runModal() }
 }
 @objc private func openDonate() {
  if let url = URL(string: "https://www.paypal.com/donate/?hosted_button_id=BG5FYMAHFG9V6") { openResource(url, title: "无法打开支持页面".localized) }
 }
 private func showAbout() {
  NSApp.orderFrontStandardAboutPanel(options: [
   .applicationName: "MacVirtualDesktopHelper",
   .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
   .credits: NSAttributedString(string: "Windows Virtual Desktop Helper 的 Mac 功能迁移。\nCopyright © 2022–2025 Dan Krusi".localized, attributes: [.font: NSFont.systemFont(ofSize: 12)])
  ])
 }
 private func openResource(_ url: URL, title: String) {
  guard !NSWorkspace.shared.open(url) else { return }
  ApplicationLog.write(title + ": " + url.absoluteString)
  let alert = NSAlert(); alert.messageText = title
  alert.informativeText = "系统未能使用默认应用打开：\n".localized + (url.isFileURL ? url.path : url.absoluteString)
  alert.runModal()
 }
 @objc private func showOverview() { overviewController?.show() }
 @objc private func spaceChanged() {
  let spaces = skyLight?.spaces() ?? []
  desktopOverlay.update(spaces: spaces, settings: overviewController?.applicationSettings.overlay ?? OverlaySettings())
  let active = spaces.filter { $0.isCurrent }
  let changed = active.filter { space in currentSpacesByDisplay[space.displayUUID].map { $0 != space.id } ?? false }
  currentSpacesByDisplay = Dictionary(active.map { ($0.displayUUID, $0.id) }, uniquingKeysWith: { first, _ in first })
  guard let space = changed.first ?? active.first else { return }
  if currentSpaceID == nil || !changed.isEmpty {
   if space.id != currentSpaceID { previousSpaceID = currentSpaceID; currentSpaceID = space.id }
  }
  if overviewController?.applicationSettings.restoreWindowFocus == true, !changed.isEmpty {
   ApplicationLog.write("Focus restore: changed=" + String(changed.count) + " remembered=" + String(lastWindows[space.id]?.id ?? 0))
  }
  // Simultaneous changes do not identify a unique display whose focus should win.
  if changed.count == 1, overviewController?.applicationSettings.restoreWindowFocus == true, let target = lastWindows[space.id] {
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
    guard let self else { return }
    let sameSpace = self.currentSpacesByDisplay[space.displayUUID] == space.id
    let enabled = self.overviewController?.applicationSettings.restoreWindowFocus == true
    let sameApp = NSRunningApplication(processIdentifier: target.pid)?.bundleIdentifier == target.bundleID
    let membership = self.skyLight?.spaceIDs(for: target.id).contains(space.id) == true
    let exists = self.accessibility.containsWindow(target)
    let overviewActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    ApplicationLog.write("Focus checks: space=" + String(sameSpace) + " enabled=" + String(enabled) + " app=" + String(sameApp) + " membership=" + String(membership) + " exists=" + String(exists) + " overview=" + String(overviewActive))
    guard sameSpace, enabled, sameApp, membership, exists, !overviewActive else { return }
    let error = self.accessibility.focus(target)
    ApplicationLog.write("Focus request: " + (error ?? "accepted"))
   }
  }
 }
 private func rememberFocusedWindow() {
  guard overviewController?.applicationSettings.restoreWindowFocus == true,
   let skyLight, let app = NSWorkspace.shared.frontmostApplication,
   app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
   let id = accessibility.focusedWindowID(pid: app.processIdentifier) else { return }
  let associated = skyLight.spaceIDs(for: id)
  // Shared windows do not identify a unique desktop to restore.
  guard associated.count == 1, let space = skyLight.spaces().first(where: { $0.isCurrent && associated.contains($0.id) }) else { return }
  if lastWindows[space.id]?.id != id { ApplicationLog.write("Focus remembered: space=" + String(space.id) + " window=" + String(id)) }
  lastWindows[space.id] = DesktopWindow(id: id, ownerName: app.localizedName ?? "", title: "", bundleID: app.bundleIdentifier ?? "", pid: app.processIdentifier, spaceID: space.id, displayUUID: space.displayUUID, isOnScreen: true, isSticky: false, icon: nil)
 }
 private func reloadHotKeys() {
  let errors = hotKeys.reload(overviewController?.applicationSettings.hotKeys ?? [])
  errors.forEach { ApplicationLog.write("Hotkey registration: " + $0) }
  if !errors.isEmpty {
   let alert = NSAlert(); alert.messageText = "部分全局快捷键注册失败".localized; alert.informativeText = errors.joined(separator: "\n"); alert.runModal()
  }
 }
 private func performHotKey(_ action: String) {
  guard let skyLight else { return }
  if action == "manager" {
   if overviewController?.applicationSettings.windowManager == "system" { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")) }
   else { overviewController?.show() }
   return
  }
  let spaces = skyLight.spaces()
  let active = spaces.first(where: { $0.id == currentSpaceID && $0.isCurrent }) ?? spaces.first(where: { $0.isCurrent })
  guard let active else { return }
  let displaySpaces = spaces.filter { $0.displayUUID == active.displayUUID }
  guard let current = displaySpaces.firstIndex(where: { $0.id == active.id }) else { return }
  var target: DesktopSpace?
  if action == "previous" { target = spaces.first { $0.id == previousSpaceID } }
  else if action == "forward", displaySpaces.indices.contains(current + 1) { target = displaySpaces[current + 1] }
  else if action == "backward", displaySpaces.indices.contains(current - 1) { target = displaySpaces[current - 1] }
  else if action.hasPrefix("desktop:"), let number = Int(action.dropFirst(8)) { target = displaySpaces.first { $0.index == number - 1 } }
  if let target { skyLight.setCurrentSpace(displayUUID: target.displayUUID, spaceID: target.id) }
 }
}
