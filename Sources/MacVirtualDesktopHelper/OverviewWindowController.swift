import AppKit

private final class OverviewGroupItem: NSObject {
	let space: DesktopSpace
	let windows: [DesktopWindow]

	init(space: DesktopSpace, windows: [DesktopWindow]) {
		self.space = space
		self.windows = windows
	}
}

final class OverviewWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate {
	private let skyLight: SkyLightService
	private let catalog: WindowCatalog
	private let accessibility: AccessibilityWindowService
	private var groups: [OverviewGroupItem] = []
	private var snapshot: WindowSnapshot?

	private let outlineView = NSOutlineView()
	private let summaryLabel = NSTextField(labelWithString: "")
	private let statusLabel = NSTextField(labelWithString: "准备就绪")
	private let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let moveButton = NSButton(title: "移动窗口", target: nil, action: nil)
	private let closeButton = NSButton(title: "关闭窗口", target: nil, action: nil)
	private let focusButton = NSButton(title: "跳转并激活", target: nil, action: nil)
	private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
	private let permissionButton = NSButton(title: "授予辅助功能权限", target: nil, action: nil)
	private let screenRecordingButton = NSButton(title: "授予屏幕录制权限", target: nil, action: nil)

	init(skyLight: SkyLightService, catalog: WindowCatalog, accessibility: AccessibilityWindowService) {
		self.skyLight = skyLight
		self.catalog = catalog
		self.accessibility = accessibility

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "MacVirtualDesktopHelper · 所有窗口"
		window.minSize = NSSize(width: 820, height: 520)
		window.isReleasedWhenClosed = false
		super.init(window: window)
		window.delegate = self
		buildInterface()
		refresh()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func show() {
		guard let window else { return }
		refresh()
		if !window.isVisible {
			window.center()
		}
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func refresh() {
		let previousSelection = selectedWindow?.id
		snapshot = catalog.snapshot()
		groups = snapshot?.groups.map { OverviewGroupItem(space: $0.space, windows: $0.windows) } ?? []
		outlineView.reloadData()
		for group in groups {
			outlineView.expandItem(group)
		}
		restoreSelection(windowID: previousSelection)
		updateSummary()
		updateTargetPopup()
		updateActionButtons()
	}

	private func buildInterface() {
		guard let window, let contentView = window.contentView else { return }
		contentView.wantsLayer = true

		let titleLabel = NSTextField(labelWithString: "所有窗口")
		titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
		let subtitleLabel = NSTextField(labelWithString: "跨原生桌面查看应用窗口；移动与激活均需手动触发")
		subtitleLabel.textColor = .secondaryLabelColor
		subtitleLabel.font = .systemFont(ofSize: 12)
		summaryLabel.textColor = .secondaryLabelColor
		summaryLabel.font = .systemFont(ofSize: 12)

		refreshButton.target = self
		refreshButton.action = #selector(refreshPressed)
		refreshButton.bezelStyle = .rounded
		permissionButton.target = self
		permissionButton.action = #selector(requestPermission)
		permissionButton.bezelStyle = .rounded
		screenRecordingButton.target = self
		screenRecordingButton.action = #selector(requestScreenRecording)
		screenRecordingButton.bezelStyle = .rounded

		let headerButtons = NSStackView(views: [permissionButton, screenRecordingButton, refreshButton])
		headerButtons.orientation = .horizontal
		headerButtons.spacing = 8

		outlineView.dataSource = self
		outlineView.delegate = self
		outlineView.headerView = NSTableHeaderView()
		outlineView.usesAlternatingRowBackgroundColors = true
		outlineView.rowSizeStyle = .medium
		outlineView.indentationPerLevel = 16
		outlineView.allowsMultipleSelection = false
		outlineView.floatsGroupRows = false
		outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		outlineView.doubleAction = #selector(focusPressed)
		outlineView.target = self

		let appColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
		appColumn.title = "应用"
		appColumn.width = 230
		appColumn.minWidth = 170
		let windowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
		windowColumn.title = "窗口"
		windowColumn.width = 500
		windowColumn.minWidth = 280
		let desktopColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("desktop"))
		desktopColumn.title = "桌面"
		desktopColumn.width = 170
		desktopColumn.minWidth = 120
		outlineView.addTableColumn(appColumn)
		outlineView.addTableColumn(windowColumn)
		outlineView.addTableColumn(desktopColumn)

		let scrollView = NSScrollView()
		scrollView.documentView = outlineView
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .bezelBorder
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		let targetLabel = NSTextField(labelWithString: "移动到")
		targetLabel.textColor = .secondaryLabelColor
		targetPopup.translatesAutoresizingMaskIntoConstraints = false
		targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
		moveButton.target = self
		moveButton.action = #selector(movePressed)
		moveButton.bezelStyle = .rounded
		focusButton.target = self
		focusButton.action = #selector(focusPressed)
		focusButton.bezelStyle = .rounded
		closeButton.target = self
		closeButton.action = #selector(closePressed)
		closeButton.bezelStyle = .rounded
		closeButton.toolTip = "关闭所选窗口；未保存内容由目标应用提示保存"

		statusLabel.textColor = .secondaryLabelColor
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let actionStack = NSStackView(views: [focusButton, targetLabel, targetPopup, moveButton, closeButton, statusLabel])
		actionStack.orientation = .horizontal
		actionStack.alignment = .centerY
		actionStack.spacing = 10
		actionStack.translatesAutoresizingMaskIntoConstraints = false

		for view in [titleLabel, subtitleLabel, summaryLabel, headerButtons, scrollView, actionStack] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(view)
		}

		NSLayoutConstraint.activate([
			titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			summaryLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 7),
			summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			headerButtons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			headerButtons.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
			scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			scrollView.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -12),
			actionStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
			actionStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
			actionStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
		])
	}

	private func updateSummary() {
		guard let snapshot else {
			summaryLabel.stringValue = "尚未读取桌面"
			return
		}
		let formatter = DateFormatter()
		formatter.dateFormat = "HH:mm:ss"
		let permission = accessibility.isTrusted ? "辅助功能已授权" : "辅助功能未授权"
		let titles = CGPreflightScreenCaptureAccess() ? "" : " · 窗口标题不可用"
		summaryLabel.stringValue = "\(snapshot.spaces.count) 个桌面 · \(snapshot.windowCount) 个窗口 · \(permission)\(titles) · 更新于 \(formatter.string(from: snapshot.capturedAt))"
		permissionButton.isHidden = accessibility.isTrusted
		screenRecordingButton.isHidden = CGPreflightScreenCaptureAccess()
	}

	private func updateTargetPopup() {
		let previousTarget = (targetPopup.selectedItem?.representedObject as? NSNumber)?.uint64Value
		targetPopup.removeAllItems()
		guard let spaces = snapshot?.spaces, !spaces.isEmpty else {
			targetPopup.isEnabled = false
			return
		}

		for space in spaces {
			let item = NSMenuItem(title: space.isCurrent ? "\(space.title)（当前）" : space.title, action: nil, keyEquivalent: "")
			item.representedObject = NSNumber(value: space.id)
			targetPopup.menu?.addItem(item)
		}
		targetPopup.isEnabled = true

		let window = selectedWindow
		let desiredTarget = previousTarget
			?? window.flatMap { selected in
				spaces.first(where: { $0.id == selected.spaceID && $0.isCurrent })?.id
					?? (window.map { selected in spaces.first(where: { $0.id != selected.spaceID })?.id } ?? nil)
			}
			?? spaces.first?.id

		if let desiredTarget, let item = targetPopup.itemArray.first(where: { ($0.representedObject as? NSNumber)?.uint64Value == desiredTarget }) {
			targetPopup.select(item)
		}
	}

	private func updateActionButtons() {
		let window = selectedWindow
		focusButton.isEnabled = window != nil
		closeButton.isEnabled = window != nil
		moveButton.isEnabled = window != nil && window?.isSticky == false && (snapshot?.spaces.count ?? 0) > 1
	}

	private func restoreSelection(windowID: CGWindowID?) {
		guard let windowID else { return }
		for row in 0..<outlineView.numberOfRows {
			if let window = outlineView.item(atRow: row) as? DesktopWindow, window.id == windowID {
				outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
				return
			}
		}
	}

	private var selectedWindow: DesktopWindow? {
		guard outlineView.selectedRow >= 0 else { return nil }
		return outlineView.item(atRow: outlineView.selectedRow) as? DesktopWindow
	}

	private func spaceTitle(for spaceID: UInt64) -> String {
		return snapshot?.spaces.first(where: { $0.id == spaceID })?.title ?? "未知桌面"
	}

	@objc private func refreshPressed() {
		refresh()
		setStatus("已刷新窗口列表。")
	}

	@objc private func movePressed() {
		guard let window = selectedWindow else {
			setStatus("请先选择一个窗口。", isError: true)
			return
		}
		guard !window.isSticky else {
			setStatus("该窗口被设置为显示在所有桌面，原型不会移动它。", isError: true)
			return
		}
		guard let targetID = (targetPopup.selectedItem?.representedObject as? NSNumber)?.uint64Value else {
			setStatus("请选择目标桌面。", isError: true)
			return
		}
		guard targetID != window.spaceID else {
			setStatus("窗口已经位于\(spaceTitle(for: targetID))。")
			return
		}

		let targetTitle = spaceTitle(for: targetID)
		skyLight.moveWindow(windowID: window.id, to: targetID)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
			guard let self else { return }
			let spaces = self.skyLight.spaceIDs(for: window.id)
			self.refresh()
			if spaces.contains(targetID) {
				self.setStatus("已将“\(window.ownerName)”移动到\(targetTitle)。")
			} else {
				self.setStatus("移动请求已发送，但没有确认到目标桌面。", isError: true)
			}
		}
	}

	@objc private func closePressed() {
		guard let target = selectedWindow else { return }
		guard accessibility.isTrusted else {
			accessibility.requestAccess()
			setStatus("请先授予辅助功能权限。", isError: true)
			return
		}
		let needsSwitch = !target.isSticky && !skyLight.spaces().contains(where: { $0.id == target.spaceID && $0.isCurrent })
		if needsSwitch {
			skyLight.setCurrentSpace(displayUUID: target.displayUUID, spaceID: target.spaceID)
		}
		waitForDesktop(target.spaceID, required: needsSwitch) { [weak self] in
			guard let self else { return }
			if let error = self.accessibility.close(target) {
				self.setStatus(error, isError: true)
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
				guard let self else { return }
				let exists = self.accessibility.containsWindow(target)
				self.refresh()
				self.setStatus(exists ? "已请求关闭；窗口仍存在，请检查保存提示或应用响应。" : "已关闭“\(target.ownerName)”的所选窗口。")
			}
		}
	}

	@objc private func focusPressed() {
		guard let window = selectedWindow else {
			setStatus("请先选择一个窗口。", isError: true)
			return
		}
		guard accessibility.isTrusted else {
			accessibility.requestAccess()
			setStatus("请先在系统设置中授予辅助功能权限，然后重试。", isError: true)
			return
		}
		let needsSwitch = snapshot?.spaces.first(where: { $0.id == window.spaceID })?.isCurrent == false
		if needsSwitch {
			skyLight.setCurrentSpace(displayUUID: window.displayUUID, spaceID: window.spaceID)
		}
		waitForDesktop(window.spaceID, required: needsSwitch) { [weak self] in
			guard let self else { return }
			if let error = self.accessibility.focus(window) {
				self.setStatus(error, isError: true)
			} else {
				self.setStatus("已激活“\(window.ownerName)”中的窗口。")
			}
			self.refresh()
		}
	}

	private func waitForDesktop(_ id: UInt64, required: Bool, attempts: Int = 60, action: @escaping () -> Void) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
			guard let self else { return }
			if !required || self.skyLight.spaces().contains(where: { $0.id == id && $0.isCurrent }) {
				action()
			} else if attempts > 0 {
				self.waitForDesktop(id, required: true, attempts: attempts - 1, action: action)
			} else {
				self.setStatus("未能切换到目标桌面，请重试。", isError: true)
			}
		}
	}

	@objc private func requestPermission() {
		if accessibility.requestAccess() {
			setStatus("辅助功能权限已授予。")
		} else {
			accessibility.openAccessibilitySettings()
			setStatus("请启用本应用，然后返回并点击刷新。", isError: true)
		}
		updateSummary()
	}

	@objc private func requestScreenRecording() {
		// Window titles come from CoreGraphics and require screen recording access.
		if CGRequestScreenCaptureAccess() {
			setStatus("屏幕录制权限已授予，正在刷新。")
		} else {
			setStatus("请在系统设置中允许屏幕录制，然后重新启动本应用。", isError: true)
		}
		updateSummary()
	}

	private func setStatus(_ text: String, isError: Bool = false) {
		statusLabel.stringValue = text
		statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if item == nil {
			return groups.count
		}
		return (item as? OverviewGroupItem)?.windows.count ?? 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let group = item as? OverviewGroupItem {
			return group.windows[index]
		}
		return groups[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return (item as? OverviewGroupItem)?.windows.isEmpty == false
	}

	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		return item is OverviewGroupItem
	}

	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		return item is DesktopWindow
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		return item is OverviewGroupItem ? 30 : 27
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		let column = tableColumn?.identifier.rawValue ?? ""
		if let group = item as? OverviewGroupItem {
			// AppKit renders group rows as a single full-width row and asks for
			// a view with a nil table column, so the title lives in that view.
			let color: NSColor = group.space.isCurrent ? .controlAccentColor : .labelColor
			let count = group.windows.isEmpty ? "无窗口" : "\(group.windows.count) 个窗口"
			let text = "\(group.space.isCurrent ? "● " : "") \(group.space.title)　\(count)"
			return labelCell(text: text, font: .systemFont(ofSize: 13, weight: .semibold), color: color)
		}

		guard let window = item as? DesktopWindow else { return nil }
		switch column {
		case "app":
			let name = window.ownerName + (window.isSticky ? "（所有桌面）" : "")
			return appCell(window: window, text: name)
		case "window":
			return labelCell(text: window.displayTitle, font: .systemFont(ofSize: 12), color: .labelColor)
		case "desktop":
			let title = spaceTitle(for: window.spaceID)
			let suffix = window.isSticky ? " · 所有桌面" : ""
			return labelCell(text: title + suffix, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
		default:
			return nil
		}
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		updateActionButtons()
		updateTargetPopup()
		if let window = selectedWindow {
			setStatus("已选择：\(window.ownerName) — \(window.displayTitle)")
		}
	}

	private func labelCell(text: String, font: NSFont, color: NSColor) -> NSTableCellView {
		let cell = NSTableCellView()
		let textField = NSTextField(labelWithString: text)
		textField.font = font
		textField.textColor = color
		textField.lineBreakMode = .byTruncatingTail
		textField.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(textField)
		NSLayoutConstraint.activate([
			textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
			textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
		])
		return cell
	}

	private func appCell(window: DesktopWindow, text: String) -> NSTableCellView {
		let cell = NSTableCellView()
		let imageView = NSImageView()
		imageView.image = window.icon
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.translatesAutoresizingMaskIntoConstraints = false
		let textField = NSTextField(labelWithString: text)
		textField.font = .systemFont(ofSize: 12)
		textField.lineBreakMode = .byTruncatingTail
		textField.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(imageView)
		cell.addSubview(textField)
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
			imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			imageView.widthAnchor.constraint(equalToConstant: 17),
			imageView.heightAnchor.constraint(equalToConstant: 17),
			textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
			textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
		])
		return cell
	}

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		sender.orderOut(nil)
		return false
	}
}
