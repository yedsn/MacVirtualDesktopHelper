import AppKit

let application = NSApplication.shared
application.applicationIconImage = TrayIconRenderer.applicationIcon()
if let bundleID = Bundle.main.bundleIdentifier,
 let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
 DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.macvirtualdesktophelper.showOverview"), object: nil, userInfo: nil, deliverImmediately: true)
 existing.activate(options: [.activateAllWindows])
 exit(0)
}
Localization.loadPersistedLanguage()
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
withExtendedLifetime(applicationDelegate) {
	application.run()
}
