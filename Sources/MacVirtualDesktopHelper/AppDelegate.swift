import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var skyLight: SkyLightService?
	private var statusBarController: StatusBarController?
	private var overviewController: OverviewWindowController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		installMainMenu()

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
			statusBar.start()

			if ProcessInfo.processInfo.arguments.contains("--show-overview") {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak overview] in
					overview?.show()
				}
			}
		} catch {
			let alert = NSAlert()
			alert.alertStyle = .critical
			alert.messageText = "无法启动 MacVirtualDesktopHelper"
			alert.informativeText = error.localizedDescription
			alert.addButton(withTitle: "退出")
			alert.runModal()
			NSApp.terminate(nil)
		}
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
		appMenu.addItem(withTitle: "关于 MacVirtualDesktopHelper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
		appMenu.addItem(NSMenuItem.separator())
		let hideItem = appMenu.addItem(withTitle: "隐藏", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		hideItem.target = NSApp
		appMenu.addItem(NSMenuItem.separator())
		let quitItem = appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		quitItem.target = NSApp
		NSApp.mainMenu = mainMenu
	}
}
