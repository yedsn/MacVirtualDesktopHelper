import AppKit

private final class OverviewGroupItem: NSObject {
	let space: DesktopSpace
	let windows: [DesktopWindow]

	init(space: DesktopSpace, windows: [DesktopWindow]) {
		self.space = space
		self.windows = windows
	}
}

final class OverviewWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate, NSSearchFieldDelegate {
	private let skyLight: SkyLightService
	private let catalog: WindowCatalog
	private let accessibility: AccessibilityWindowService
	private var groups: [OverviewGroupItem] = []
	private var snapshot: WindowSnapshot?
 private let windowReview = WindowReview()
 private var ruleStore: RuleStore?
 private var snapshotScheduler: SnapshotScheduler?
 private var settingsController: SettingsController?
 var settingsChanged: (() -> Void)?
 var applicationSettings: ApplicationSettings { ruleStore?.state.settings ?? ApplicationSettings() }
 private var bulkRunning = false
 private var lockEditor: RuleEditor?
 private var desktopEditor: RuleEditor?
 private var snapshotsController: SnapshotController?
 private let catalogQueue = DispatchQueue(label: "local.macvirtualdesktophelper.catalog", qos: .userInitiated)
 private var refreshGeneration = 0
 private var loading = false
 private let loadingIndicator = NSProgressIndicator()
 private let backdrop = NSVisualEffectView()

	private let outlineView = NSOutlineView()
 private let grid = NSView()
 private var cards: [DesktopCardView] = []
 private var cardSelection: DesktopWindow?
	private let summaryLabel = NSTextField(labelWithString: "")
	private let searchField = NSSearchField()
	private let statusLabel = NSTextField(labelWithString: "准备就绪".localized)
	private let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let moveButton = NSButton(title: "移动窗口".localized, target: nil, action: nil)
	private let closeButton = NSButton(title: "关闭窗口".localized, target: nil, action: nil)
	private let focusButton = NSButton(title: "跳转并激活".localized, target: nil, action: nil)
	private let refreshButton = NSButton(title: "刷新".localized, target: nil, action: nil)
 private let snapshotsButton = NSButton(title: "快照".localized, target: nil, action: nil)
	private let permissionButton = NSButton(title: "授予辅助功能权限".localized, target: nil, action: nil)
	private let screenRecordingButton = NSButton(title: "授予屏幕录制权限".localized, target: nil, action: nil)
 private let lockAllButton = NSButton(title: "更新锁定规则".localized, target: nil, action: nil)
 private let manageLocksButton = NSButton(title: "管理锁定规则".localized, target: nil, action: nil)
 private let updateRulesButton = NSButton(title: "更新桌面规则".localized, target: nil, action: nil)
 private let manageRulesButton = NSButton(title: "管理桌面规则".localized, target: nil, action: nil)
 private let applyRulesButton = NSButton(title: "应用桌面规则".localized, target: nil, action: nil)
 private let cleanupButton = NSButton(title: "一键清理 (0)".localized, target: nil, action: nil)

	init(skyLight: SkyLightService, catalog: WindowCatalog, accessibility: AccessibilityWindowService) {
		self.skyLight = skyLight
		self.catalog = catalog
		self.accessibility = accessibility

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 1120, height: 640),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "MacVirtualDesktopHelper · 所有窗口".localized
		window.minSize = NSSize(width: 1100, height: 460)
		window.isReleasedWhenClosed = false
		super.init(window: window)
		window.delegate = self
		buildInterface()
  do {
   let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
   ruleStore = try RuleStore(url: support.appendingPathComponent("MacVirtualDesktopHelper/desktop-rule-state.json"))
   if let ruleStore {
    let scheduler = SnapshotScheduler(store: ruleStore)
    scheduler.captured = { [weak self] in self?.snapshotsController?.reload() }
    scheduler.failed = { error in ApplicationLog.write("Automatic snapshot failed: " + error.localizedDescription) }
    scheduler.reload()
    snapshotScheduler = scheduler
   }
  } catch {
   let alert = NSAlert(error: error)
   alert.runModal()
  }
		refresh()
  applyAppearance()
	}
 func showSettings() {
  guard let ruleStore else { return }
  if settingsController == nil {
   settingsController = SettingsController(store: ruleStore)
   settingsController?.changed = { [weak self] in self?.applyAppearance(); self?.settingsChanged?() }
   settingsController?.openSnapshots = { [weak self] in self?.showSnapshots() }
   settingsController?.exportConfiguration = { [weak self] in self?.showSnapshots(); self?.snapshotsController?.exportBackup() }
   settingsController?.importConfiguration = { [weak self] in self?.showSnapshots(); self?.snapshotsController?.importBackup(); self?.settingsController?.reload() }
  }
  settingsController?.reload(); settingsController?.window?.center(); settingsController?.showWindow(nil)
 }
 private func applyAppearance() {
  switch applicationSettings.theme {
  case "light": NSApp.appearance = NSAppearance(named: .aqua)
  case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
  default: NSApp.appearance = nil
  }
  let glass = applicationSettings.frostedWindow ?? true
  backdrop.isHidden = !glass
  window?.isOpaque = !glass
  window?.backgroundColor = glass ? NSColor.windowBackgroundColor.withAlphaComponent(0.92) : .windowBackgroundColor
  // Keep AppKit's tinted titlebar material; a transparent titlebar has no
  // backing effect because the content backdrop only covers the content area.
  window?.titlebarAppearsTransparent = false
  renderCards()
  updateDockPresence()
 }
 private func updateDockPresence() {
  NSApp.setActivationPolicy((applicationSettings.showDockIcon ?? true) && window?.isVisible == true ? .regular : .accessory)
 }
 func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func show() {
  if let modal = NSApp.modalWindow {
   NSApp.unhide(nil)
   modal.makeKeyAndOrderFront(nil)
   NSApp.activate(ignoringOtherApps: true)
   return
  }
		guard let window else { return }
  if applicationSettings.showDockIcon ?? true { NSApp.setActivationPolicy(.regular) }
		refreshInBackground()
		if !window.isVisible {
			window.center()
		}
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		window.makeFirstResponder(searchField)
		searchField.selectText(nil)
	}

	func refresh() {
  refreshGeneration += 1
  finishLoading()
  lockEditor?.reloadRules()
  desktopEditor?.reloadRules()
		statusLabel.stringValue = "正在读取打开的窗口…".localized
		snapshot = catalog.snapshot()
		filterSnapshot()
	}

 private func finishLoading() {
  loading = false
  loadingIndicator.stopAnimation(nil)
  loadingIndicator.isHidden = true
 }
 private func refreshInBackground() {
  guard !bulkRunning else { return }
  refreshGeneration += 1
  let generation = refreshGeneration
  loading = true
  loadingIndicator.isHidden = false
  loadingIndicator.startAnimation(nil)
  setStatus("正在读取打开的窗口…".localized)
  updateActionButtons()
  let catalog = self.catalog
  catalogQueue.async { [weak self] in
   let next = catalog.snapshot()
   DispatchQueue.main.async { [weak self] in
    guard let self, self.refreshGeneration == generation else { return }
    self.snapshot = next
    self.finishLoading()
    self.filterSnapshot()
   }
  }
 }

	private func filterSnapshot() {
		let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let displayedGroups = WindowSnapshot.overviewGroups(snapshot?.groups ?? [])
		groups = displayedGroups.map { group in
			OverviewGroupItem(space: group.space, windows: group.windows.filter {
				query.isEmpty || $0.ownerName.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
			})
		}
		renderCards()
  outlineView.reloadData()
		for group in groups {
			outlineView.expandItem(group)
		}
		updateSummary()
		updateTargetPopup()
		updateActionButtons()
  let visibleCount = Set(groups.flatMap { $0.windows.map(\.id) }).count
		setStatus(loading ? "正在读取打开的窗口…".localized : "找到 ".localized + String(visibleCount) + " 个窗口".localized)
	}

	private func buildInterface() {
		guard let window, let contentView = window.contentView else { return }
		contentView.wantsLayer = true
  backdrop.frame = contentView.bounds
  backdrop.autoresizingMask = [.width, .height]
  backdrop.material = .sidebar; backdrop.blendingMode = .behindWindow; backdrop.state = .active
  contentView.addSubview(backdrop, positioned: .below, relativeTo: nil)

		let titleLabel = NSTextField(labelWithString: "所有窗口".localized)
		titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
		let subtitleLabel = NSTextField(labelWithString: "跨原生桌面查看应用窗口；移动与激活均需手动触发".localized)
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

  snapshotsButton.target = self; snapshotsButton.action = #selector(showSnapshots)
		let headerButtons = NSStackView(views: [permissionButton, screenRecordingButton, refreshButton, snapshotsButton])
		searchField.placeholderString = "搜索应用或窗口标题".localized
		searchField.delegate = self
  searchField.target = self
  searchField.action = #selector(searchChanged)
		searchField.sendsSearchStringImmediately = true
		searchField.setAccessibilityLabel("搜索应用或窗口标题".localized)
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
		appColumn.title = "应用".localized
		appColumn.width = 230
		appColumn.minWidth = 170
		let windowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
		windowColumn.title = "窗口".localized
		windowColumn.width = 500
		windowColumn.minWidth = 280
		let desktopColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("desktop"))
		desktopColumn.title = "桌面".localized
		desktopColumn.width = 170
		desktopColumn.minWidth = 120
		outlineView.addTableColumn(appColumn)
		outlineView.addTableColumn(windowColumn)
		outlineView.addTableColumn(desktopColumn)

		let scrollView = NSScrollView()
		scrollView.documentView = grid
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .bezelBorder
		scrollView.translatesAutoresizingMaskIntoConstraints = false
  loadingIndicator.style = .spinning
  loadingIndicator.controlSize = .regular
  loadingIndicator.isHidden = true
  loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
  contentView.addSubview(loadingIndicator)
  NSLayoutConstraint.activate([loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)])

		let targetLabel = NSTextField(labelWithString: "移动到".localized)
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
		closeButton.toolTip = "关闭所选窗口；未保存内容由目标应用提示保存".localized

		statusLabel.textColor = .secondaryLabelColor
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  statusLabel.setContentHuggingPriority(.init(1), for: .horizontal)
  statusLabel.toolTip = "窗口数量、当前选择与操作结果".localized

  lockAllButton.target = self; lockAllButton.action = #selector(updateCleanupRules)
  cleanupButton.target = self; cleanupButton.action = #selector(cleanupWindows)
  manageLocksButton.target = self; manageLocksButton.action = #selector(manageLocks)
  updateRulesButton.target = self; updateRulesButton.action = #selector(updateDesktopRules)
  manageRulesButton.target = self; manageRulesButton.action = #selector(manageDesktopRules)
  applyRulesButton.target = self; applyRulesButton.action = #selector(applyDesktopRules)
  // Match the Windows bottom panel's rendered DockStyle.Right group order.
		let actionStack = NSStackView(views: [statusLabel, focusButton, closeButton, updateRulesButton, manageRulesButton, applyRulesButton, lockAllButton, manageLocksButton, cleanupButton])
		actionStack.orientation = .horizontal
		actionStack.alignment = .centerY
		actionStack.spacing = 10
  actionStack.setCustomSpacing(20, after: closeButton)
  actionStack.setCustomSpacing(20, after: applyRulesButton)
  actionStack.distribution = .fill
  for button in [lockAllButton, manageLocksButton, cleanupButton, updateRulesButton, manageRulesButton, applyRulesButton, focusButton, closeButton] {
   button.setContentHuggingPriority(.required, for: .horizontal)
   button.setContentCompressionResistancePriority(.required, for: .horizontal)
  }
		actionStack.translatesAutoresizingMaskIntoConstraints = false

		titleLabel.isHidden = true
		subtitleLabel.isHidden = true
		summaryLabel.isHidden = true
		focusButton.title = "激活窗口".localized
		for view in [titleLabel, subtitleLabel, summaryLabel, headerButtons, searchField, scrollView, actionStack] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(view)
		}
  contentView.addSubview(loadingIndicator, positioned: .above, relativeTo: scrollView)

		NSLayoutConstraint.activate([
			titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			summaryLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 7),
			summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			headerButtons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			headerButtons.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
			searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
			searchField.trailingAnchor.constraint(equalTo: headerButtons.leadingAnchor, constant: -10),
			scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			scrollView.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -12),
			actionStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
			actionStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
			actionStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
		])
	}

	func controlTextDidChange(_ notification: Notification) {
		filterSnapshot()
	}
 @objc private func searchChanged() { filterSnapshot() }

 func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
  if commandSelector == #selector(NSResponder.cancelOperation(_:)) { window?.performClose(nil); return true }
  if commandSelector == #selector(NSResponder.insertNewline(_:)), selectedWindow != nil { activateSelected(hideAfter: true); return true }
  if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.moveUp(_:)) {
   let movingUp = commandSelector == #selector(NSResponder.moveUp(_:))
   let populated = cards.filter { !$0.group.windows.isEmpty }
   guard let card = movingUp ? populated.last : populated.first else { return false }
   let row = movingUp ? card.group.windows.count - 1 : 0
   card.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
   window?.makeFirstResponder(card.table)
   card.scrollToVisible(card.bounds)
   card.table.scrollRowToVisible(row)
   return true
  }
  return false
 }

	private func updateSummary() {
		guard let snapshot else {
			summaryLabel.stringValue = "尚未读取桌面".localized
			return
		}
		let formatter = DateFormatter()
		formatter.dateFormat = "HH:mm:ss"
		let permission = accessibility.isTrusted ? "辅助功能已授权".localized : "辅助功能未授权".localized
		let titles = CGPreflightScreenCaptureAccess() ? "" : " · 窗口标题不可用".localized
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
  if loading {
   for button in [focusButton, closeButton, moveButton, cleanupButton, lockAllButton, manageLocksButton, updateRulesButton, manageRulesButton, applyRulesButton, snapshotsButton] { button.isEnabled = false }
   return
  }
		let window = selectedWindow
		focusButton.isEnabled = window != nil && !bulkRunning
		closeButton.isEnabled = window != nil && !bulkRunning
		moveButton.isEnabled = !bulkRunning && window != nil && window?.isSticky == false && (snapshot?.spaces.count ?? 0) > 1
		let cleanupWindows = uniqueWindows.filter { !$0.belongsToBackgroundSection }
		cleanupButton.title = "一键清理 (".localized + String(cleanupWindows.filter { !isCleanupLocked($0) }.count) + ")"
		cleanupButton.contentTintColor = cleanupWindows.contains(where: { !isCleanupLocked($0) }) ? NSColor(srgbRed: 178.0 / 255, green: 34.0 / 255, blue: 34.0 / 255, alpha: 1) : .controlTextColor
  cleanupButton.attributedTitle = NSAttributedString(string: cleanupButton.title, attributes: [.foregroundColor: cleanupButton.contentTintColor ?? NSColor.controlTextColor, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
  cleanupButton.isEnabled = ruleStore != nil && !bulkRunning
  lockAllButton.isEnabled = ruleStore != nil && !bulkRunning
  for button in [manageLocksButton, updateRulesButton, manageRulesButton, applyRulesButton, snapshotsButton] { button.isEnabled = ruleStore != nil && !bulkRunning }
	}

 private var uniqueWindows: [DesktopWindow] {
  var seen = Set<UInt32>()
  return (snapshot?.groups.flatMap(\.windows) ?? []).filter { seen.insert($0.id).inserted }
 }
 @objc private func manageLocks() {
  guard let ruleStore else { return }
  if lockEditor == nil {
   lockEditor = RuleEditor(store: ruleStore)
   lockEditor?.changed = { [weak self] in
    self?.cards.forEach { $0.table.reloadData() }
    self?.updateActionButtons()
   }
  }
  lockEditor?.window?.center()
  lockEditor?.showWindow(nil)
 }

 private var ruleWindows: [RuleWindowIdentity] {
  uniqueWindows.compactMap { item in
   guard !item.isSticky, let space = snapshot?.spaces.first(where: { $0.id == item.spaceID }) else { return nil }
   return RuleWindowIdentity(id: item.id, bundleID: item.bundleID, applicationPath: NSRunningApplication(processIdentifier: item.pid)?.bundleURL?.path ?? "", title: item.title, spaceUUID: space.uuid, displayUUID: space.displayUUID, desktopIndex: space.index)
  }
 }

 @objc private func manageDesktopRules() {
  guard let ruleStore else { return }
  if desktopEditor == nil { desktopEditor = RuleEditor(store: ruleStore, desktopMode: true, spaces: { [weak self] in self?.skyLight.spaces() ?? [] }) }
  desktopEditor?.window?.center(); desktopEditor?.showWindow(nil)
 }
 @objc func showSnapshots() {
  guard let ruleStore else { return }
  if snapshotsController == nil {
   snapshotsController = SnapshotController(store: ruleStore)
   snapshotsController?.changed = { [weak self] in
    guard let self else { return }
    self.refresh()
    self.applyAppearance()
    self.settingsController?.reload()
    self.lockEditor?.reloadRules()
    self.desktopEditor?.reloadRules()
    self.settingsChanged?()
   }
   snapshotsController?.scheduleChanged = { [weak self] in self?.snapshotScheduler?.reload() }
  }
  snapshotsController?.window?.center(); snapshotsController?.showWindow(nil)
 }

 private func targetSpace(_ rule: WindowRule) -> DesktopSpace? {
  let spaces = skyLight.spaces()
  let targets = spaces.map { DesktopRuleMatcher.Target(uuid: $0.uuid, displayUUID: $0.displayUUID, index: $0.index) }
  guard let index = DesktopRuleMatcher.targetIndex(for: rule, targets: targets) else { return nil }
  return spaces[index]
 }

 @objc private func applyDesktopRules() {
  guard !bulkRunning, !loading else { return }
  guard let ruleStore else { setStatus("规则状态不可用，无法应用桌面规则。".localized, isError: true); return }
  guard CGPreflightScreenCaptureAccess() else { setStatus("请先授予屏幕录制权限，以读取标题并匹配桌面规则。".localized, isError: true); return }
  snapshot = catalog.snapshot()
  let identities = ruleWindows
  let missingTargets = ruleStore.state.desktopRules.filter { targetSpace($0) == nil }.count
  let movable = ruleStore.state.desktopRules.compactMap { rule -> DesktopWindow? in
   guard let match = DesktopRuleMatcher.uniqueWindow(for: rule, rules: ruleStore.state.desktopRules, windows: identities),
    let target = targetSpace(rule), target.uuid != match.spaceUUID else { return nil }
   return uniqueWindows.first { $0.id == match.id }
  }
  guard !movable.isEmpty else { setStatus("没有可移动的唯一匹配窗口；目标缺失规则 ".localized + String(missingTargets) + " 条，歧义及已归位项保持不动。".localized); return }
  var previewDetails: [UInt32: String] = [:]
  for item in movable {
   if let rule = ruleStore.state.desktopRules.first(where: { DesktopRuleMatcher.uniqueWindow(for: $0, rules: ruleStore.state.desktopRules, windows: identities)?.id == item.id }), let target = targetSpace(rule) {
    let source = snapshot?.spaces.first(where: { $0.id == item.spaceID })?.title ?? "未知归属".localized
    previewDetails[item.id] = source + " → " + target.title
   }
  }
  let approvedRules = ruleStore.state.desktopRules
  guard let accepted = windowReview.confirm(title: "应用桌面规则".localized, windows: movable, action: "确认应用".localized, details: previewDetails) else { return }
  bulkRunning = true; updateActionButtons()
  applyNext(accepted, approvedRules: approvedRules, moved: 0, failed: 0)
 }

 private func applyNext(_ candidates: [DesktopWindow], approvedRules: [WindowRule], moved: Int, failed: Int) {
  snapshot = catalog.snapshot()
  guard let candidate = candidates.first, let ruleStore else {
   bulkRunning = false; refresh()
   setStatus("规则应用完成：移动 ".localized + String(moved) + " 个，跳过或失败 ".localized + String(failed) + " 个。".localized); return
  }
  setStatus("正在应用桌面规则：已处理 ".localized + String(moved + failed) + " 个，剩余 ".localized + String(candidates.count) + " 个…".localized)
  let identities = ruleWindows
  guard let current = identities.first(where: { $0.id == candidate.id }),
   let live = uniqueWindows.first(where: { $0.id == candidate.id && $0.pid == candidate.pid && $0.bundleID == candidate.bundleID && $0.title == candidate.title }),
   let rule = ruleStore.state.desktopRules.first(where: { DesktopRuleMatcher.uniqueWindow(for: $0, rules: ruleStore.state.desktopRules, windows: identities)?.id == current.id }),
   let approved = approvedRules.first(where: { $0.id == rule.id }),
   DesktopRuleChange(windowID: candidate.id, rule: approved, isNew: false).agrees(with: DesktopRuleChange(windowID: candidate.id, rule: rule, isNew: false)),
   let target = targetSpace(rule), !live.isSticky else {
   ApplicationLog.write("Rule application skipped: candidate revalidation failed, window=" + String(candidate.id))
   DispatchQueue.main.async { [weak self] in self?.applyNext(Array(candidates.dropFirst()), approvedRules: approvedRules, moved: moved, failed: failed + 1) }; return
  }
  // A window may have been moved manually while the preview was open.
  // Count it as skipped rather than claiming this operation moved it.
  guard current.spaceUUID != target.uuid || current.displayUUID != target.displayUUID else {
   ApplicationLog.write("Rule application skipped: already at target, window=" + String(candidate.id))
   DispatchQueue.main.async { [weak self] in self?.applyNext(Array(candidates.dropFirst()), approvedRules: approvedRules, moved: moved, failed: failed + 1) }; return
  }
  ApplicationLog.write("Rule move requested: window=" + String(live.id) + " source=" + String(live.spaceID) + " target=" + String(target.id))
  skyLight.moveWindow(windowID: live.id, to: target.id)
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
   guard let self else { return }
   let memberships = Set(self.skyLight.spaceIDs(for: live.id))
   let identitySurvives = NSRunningApplication(processIdentifier: live.pid)?.bundleIdentifier == live.bundleID
   let descriptions = CGWindowListCopyWindowInfo(.optionIncludingWindow, live.id) as? [[String: Any]] ?? []
   let windowSurvives = descriptions.contains { info in
    (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value == live.id &&
     (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == live.pid
   }
   ApplicationLog.write("Rule move result: window=" + String(live.id) + " memberships=" + memberships.sorted().map(String.init).joined(separator: ",") + " identity=" + String(identitySurvives) + " ownedWindow=" + String(windowSurvives))
   let success = memberships == Set([target.id]) &&
    identitySurvives && windowSurvives
   self.setStatus("正在应用桌面规则，剩余 ".localized + String(candidates.count - 1) + " 个…".localized)
   self.applyNext(Array(candidates.dropFirst()), approvedRules: approvedRules, moved: moved + (success ? 1 : 0), failed: failed + (success ? 0 : 1))
  }
 }

 @objc private func updateDesktopRules() {
  guard !bulkRunning, !loading else { return }
  guard let ruleStore else { setStatus("规则状态不可用，无法更新桌面规则。".localized, isError: true); return }
  guard CGPreflightScreenCaptureAccess() else { setStatus("请先授予屏幕录制权限，以读取标题并更新桌面规则。".localized, isError: true); return }
  snapshot = catalog.snapshot()
  let update = DesktopRuleMatcher.update(rules: ruleStore.state.desktopRules, windows: ruleWindows)
  let ids = Set(update.changes.map(\.windowID))
  guard !ids.isEmpty else {
   setStatus("无需更新；存在歧义的窗口：".localized + String(update.ambiguousWindowIDs.count)); return
  }
  var previewDetails: [UInt32: String] = [:]
  for change in update.changes {
   let target = targetSpace(change.rule)?.title ?? "目标桌面缺失".localized
   previewDetails[change.windowID] = (change.isNew ? "新增 → ".localized : "更新 → ".localized) + target
  }
  guard let reviewed = windowReview.confirm(title: "检查桌面规则更改".localized, windows: uniqueWindows.filter { ids.contains($0.id) }, action: "保存桌面规则".localized, details: previewDetails) else { return }
  let accepted = Set(reviewed.map(\.id))
  snapshot = catalog.snapshot()
  let currentUpdate = DesktopRuleMatcher.update(rules: ruleStore.state.desktopRules, windows: ruleWindows)
  let validChanges = update.changes.filter { original in
   guard accepted.contains(original.windowID),
    let live = uniqueWindows.first(where: { $0.id == original.windowID }),
    let preview = reviewed.first(where: { $0.id == original.windowID }),
    live.pid == preview.pid, live.bundleID == preview.bundleID, live.title == preview.title else { return false }
   return currentUpdate.changes.contains { original.agrees(with: $0) }
  }
  do {
   try ruleStore.update { state in
    for change in validChanges {
     if let index = state.desktopRules.firstIndex(where: { $0.id == change.rule.id }) { state.desktopRules[index] = change.rule }
     else { state.desktopRules.append(change.rule) }
    }
   }
   setStatus("已保存 ".localized + String(validChanges.count) + " 条桌面规则；预览后变化跳过 ".localized + String(accepted.count - validChanges.count) + " 个，歧义跳过 ".localized + String(currentUpdate.ambiguousWindowIDs.count) + " 个窗口。".localized)
  } catch { setStatus(error.localizedDescription, isError: true) }
 }

 @objc private func updateCleanupRules() {
  guard !bulkRunning, !loading else { return }
  guard let ruleStore else { setStatus("规则状态不可用，无法更新锁定规则。".localized, isError: true); return }
  guard CGPreflightScreenCaptureAccess() else { setStatus("请先授予屏幕录制权限，以读取标题并更新锁定规则。".localized, isError: true); return }
  snapshot = catalog.snapshot()
  guard let windows = windowReview.confirm(title: "检查锁定规则".localized, windows: uniqueWindows.filter(\.hasKnownSpace), action: "更新锁定规则".localized) else { return }
  snapshot = catalog.snapshot()
  let currentWindows = uniqueWindows
  let validWindows = windows.filter { preview in
   currentWindows.contains { live in
    live.id == preview.id && live.pid == preview.pid && live.bundleID == preview.bundleID &&
    live.title == preview.title && live.hasKnownSpace
   }
  }
  var added = 0
  do {
   try ruleStore.update { state in
    for item in validWindows {
     let path = NSRunningApplication(processIdentifier: item.pid)?.bundleURL?.path ?? ""
     if !state.cleanupRules.contains(where: { $0.matches(bundleID: item.bundleID, applicationPath: path, title: item.title) }) {
      state.cleanupRules.append(WindowRule(bundleID: item.bundleID, applicationPath: path, title: item.title))
      added += 1
     }
    }
   }
   cards.forEach { card in
    let selection = card.table.selectedRowIndexes
    card.table.reloadData()
    card.table.selectRowIndexes(selection, byExtendingSelection: false)
   }
   updateActionButtons()
   setStatus("新增锁定规则 ".localized + String(added) + " 条；预览后变化跳过 ".localized + String(windows.count - validWindows.count) + " 个窗口。".localized)
  } catch { setStatus(error.localizedDescription, isError: true) }
 }

 @objc private func cleanupWindows() {
  guard !bulkRunning, !loading else { return }
  guard accessibility.isTrusted, CGPreflightScreenCaptureAccess(), ruleStore != nil else {
   setStatus("请先授予辅助功能及窗口标题读取权限。".localized, isError: true); return
  }
  snapshot = catalog.snapshot()
		let candidates = uniqueWindows.filter { !$0.belongsToBackgroundSection && !isCleanupLocked($0) }
  guard !candidates.isEmpty else { setStatus("所有桌面均无未保护窗口。".localized); return }
  guard let reviewed = windowReview.confirm(title: "一键清理".localized, windows: candidates, action: "确认清理".localized) else { return }
  bulkRunning = true
  updateActionButtons()
  closeNext(reviewed, closed: 0, remaining: 0, failed: 0)
 }

 private func closeNext(_ candidates: [DesktopWindow], closed: Int, remaining: Int, failed: Int) {
  snapshot = catalog.snapshot()
  guard let item = candidates.first else {
   bulkRunning = false
   refresh()
   setStatus("清理完成：已关闭 ".localized + String(closed) + " 个，仍存在 ".localized + String(remaining) + " 个，跳过或失败 ".localized + String(failed) + " 个；仍存在的窗口可能等待保存或应用响应。".localized)
   return
  }
  setStatus("正在清理：已关闭 ".localized + String(closed) + " 个，等待响应 ".localized + String(remaining) + " 个，跳过或失败 ".localized + String(failed) + " 个，剩余 ".localized + String(candidates.count) + " 个…".localized)
  guard let current = item.cleanupCandidate(in: uniqueWindows, isProtected: isCleanupLocked) else {
   DispatchQueue.main.async { [weak self] in self?.closeNext(Array(candidates.dropFirst()), closed: closed, remaining: remaining, failed: failed + 1) }; return
  }
		let needsSwitch = !current.belongsToBackgroundSection && !current.isSticky && !skyLight.spaces().contains { $0.id == current.spaceID && $0.isCurrent }
  if needsSwitch { skyLight.setCurrentSpace(displayUUID: current.displayUUID, spaceID: current.spaceID) }
  waitForDesktop(current.spaceID, required: needsSwitch, onFailure: { [weak self] in
   self?.closeNext(Array(candidates.dropFirst()), closed: closed, remaining: remaining, failed: failed + 1)
  }) { [weak self] in
   guard let self else { return }
   self.snapshot = self.catalog.snapshot()
   let live = current.cleanupCandidate(in: self.uniqueWindows, isProtected: self.isCleanupLocked)
   let error: String?
   if let live { error = self.accessibility.close(live) }
   else { error = "窗口身份或保护状态已改变".localized }
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
    guard let self else { return }
    self.snapshot = self.catalog.snapshot()
    let presence = error == nil ? self.accessibility.windowPresence(current) : nil
    self.closeNext(Array(candidates.dropFirst()), closed: closed + (presence == false ? 1 : 0), remaining: remaining + (presence == true ? 1 : 0), failed: failed + (presence == nil ? 1 : 0))
   }
  }
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
		return cardSelection
	}

 private func renderCards() {
  let previous = cardSelection?.id
  let previousSpace = cards.first(where: { $0.table.selectedRow >= 0 })?.group.space.id
  let hadTableFocus = cards.contains { $0.table === window?.firstResponder }
  if hadTableFocus { window?.makeFirstResponder(nil) }
  cardSelection = nil
  grid.subviews.forEach { $0.removeFromSuperview() }
  cards = groups.map { DesktopCardView(group: WindowGroup(space: $0.space, windows: $0.windows), fontSize: CGFloat(applicationSettings.overviewFontSize ?? 14), solidBackground: !(applicationSettings.frostedWindow ?? true)) }
  let rows = max(1, Int(ceil(Double(cards.count) / 3)))
  let viewport = grid.enclosingScrollView?.contentSize ?? NSSize(width: 1000, height: 540)
  let cardHeight = max(150, (viewport.height - CGFloat(rows + 1) * 10) / CGFloat(rows))
  grid.frame = NSRect(x: 0, y: 0, width: viewport.width, height: max(viewport.height, CGFloat(rows) * (cardHeight + 10) + 10))
  for (index, card) in cards.enumerated() {
   grid.addSubview(card)
   card.isLocked = { [weak self] item in self?.isCleanupLocked(item) ?? false }
   card.onToggleLock = { [weak self] item in self?.toggleCleanupLock(item) }
   card.table.reloadData()
   card.onSelect = { [weak self, weak card] selected in
    guard let self else { return }
    self.cardSelection = selected
    for other in self.cards where other !== card { other.table.deselectAll(nil) }
    self.updateActionButtons()
    self.setStatus(selected.ownerName + " — " + selected.displayTitle)
   }
   card.onActivate = { [weak self] in self?.activateSelected(hideAfter: true) }
   card.onDrop = { [weak self] id, destination in
    guard let self, !self.loading, !self.bulkRunning, let item = self.snapshot?.groups.flatMap(\.windows).first(where: { $0.id == id }), !item.isSticky else { return }
    self.cardSelection = item
    self.updateTargetPopup()
    if let menuItem = self.targetPopup.itemArray.first(where: { ($0.representedObject as? NSNumber)?.uint64Value == destination }) {
     self.targetPopup.select(menuItem)
     self.movePressed()
    }
   }
   card.table.navigate = { [weak self, weak card] key in
    guard let self, let card, [123, 124, 125, 126].contains(key) else { return false }
    let row = card.table.selectedRow
    if key == 125, row + 1 < card.group.windows.count { return false }
    if key == 126, row > 0 { return false }
    let step = key == 123 ? -1 : key == 124 ? 1 : key == 125 ? 3 : -3
    var target = index + step
    while target >= 0 && target < self.cards.count {
     let next = self.cards[target]
     if !next.group.windows.isEmpty {
      let nextRow = key == 125 ? 0 : key == 126 ? next.group.windows.count - 1 : max(0, min(row, next.group.windows.count - 1))
      next.table.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
      self.window?.makeFirstResponder(next.table)
      next.scrollToVisible(next.bounds)
      next.table.scrollRowToVisible(nextRow)
      return true
     }
     target += step
    }
    return true
   }
   let width = (grid.bounds.width - 40) / 3
   card.frame = NSRect(x: 10 + CGFloat(index % 3) * (width + 10), y: grid.bounds.height - 10 - CGFloat(index / 3 + 1) * (cardHeight + 10) + 10, width: width, height: cardHeight)
  }
  let restored = cards.first(where: { $0.group.space.id == previousSpace && $0.group.windows.contains(where: { $0.id == previous }) })
   ?? cards.first(where: { $0.group.windows.contains(where: { $0.id == previous }) })
  if let restored, let row = restored.group.windows.firstIndex(where: { $0.id == previous }) {
   restored.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
   restored.table.scrollRowToVisible(row)
   if hadTableFocus { window?.makeFirstResponder(restored.table) }
  }
  updateActionButtons()
 }

 func windowDidResize(_ notification: Notification) { renderCards() }

 private func isCleanupLocked(_ item: DesktopWindow) -> Bool {
  guard item.hasKnownSpace else { return true }
  let path = NSRunningApplication(processIdentifier: item.pid)?.bundleURL?.path ?? ""
  // An inconclusive protection check must never make a window eligible for cleanup.
  return ruleStore?.state.cleanupRules.contains { $0.matchResult(bundleID: item.bundleID, applicationPath: path, title: item.title) != .notMatched } ?? true
 }

 private func toggleCleanupLock(_ item: DesktopWindow) {
  guard !bulkRunning, !loading else { return }
  guard item.hasKnownSpace else { setStatus("无法确定桌面归属，暂不参与清理与规则操作。".localized, isError: true); return }
  guard CGPreflightScreenCaptureAccess() else {
   setStatus("请先授予屏幕录制权限，以窗口标题区分清理保护规则。".localized, isError: true)
   return
  }
  guard let ruleStore else { setStatus("规则状态不可用，无法修改清理保护。".localized, isError: true); return }
  let path = NSRunningApplication(processIdentifier: item.pid)?.bundleURL?.path ?? ""
  do {
   let locked = isCleanupLocked(item)
   try ruleStore.update { state in
    if locked {
     state.cleanupRules.removeAll { $0.matches(bundleID: item.bundleID, applicationPath: path, title: item.title) }
    } else {
     state.cleanupRules.append(WindowRule(bundleID: item.bundleID, applicationPath: path, title: item.title))
    }
   }
   cards.forEach { card in
    let selection = card.table.selectedRowIndexes
    card.table.reloadData()
    card.table.selectRowIndexes(selection, byExtendingSelection: false)
   }
   updateActionButtons()
   setStatus(isCleanupLocked(item) ? "窗口受清理保护；无法确定的匹配需在规则管理器检查。".localized : "已解除清理保护。".localized)
  } catch { setStatus(error.localizedDescription, isError: true) }
 }

	private func spaceTitle(for spaceID: UInt64) -> String {
		return snapshot?.spaces.first(where: { $0.id == spaceID })?.title ?? "未知桌面".localized
	}

	@objc private func refreshPressed() {
		refreshInBackground()
	}

	@objc private func movePressed() {
  guard !bulkRunning, !loading else { return }
		guard let window = selectedWindow else {
			setStatus("请先选择一个窗口。".localized, isError: true)
			return
		}
		if window.isAccessibilityUnavailable {
			setStatus("该后台窗口未提供辅助功能接口，无法激活；请从应用自身菜单或图标打开。".localized, isError: true)
			return
		}
		guard !window.isSticky, window.hasKnownSpace else {
			setStatus("该窗口被设置为显示在所有桌面，原型不会移动它。".localized, isError: true)
			return
		}
		guard let targetID = (targetPopup.selectedItem?.representedObject as? NSNumber)?.uint64Value else {
			setStatus("请选择目标桌面。".localized, isError: true)
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
				self.setStatus("移动请求已发送，但没有确认到目标桌面。".localized, isError: true)
			}
		}
	}

	@objc private func closePressed() {
  guard !bulkRunning, !loading else { return }
		guard let target = selectedWindow else { return }
		guard accessibility.isTrusted else {
			accessibility.requestAccess()
			setStatus("请先授予辅助功能权限。".localized, isError: true)
			return
		}
		let needsSwitch = target.hasKnownSpace && !target.belongsToBackgroundSection && !target.isSticky && !skyLight.spaces().contains(where: { $0.id == target.spaceID && $0.isCurrent })
		if needsSwitch {
			skyLight.setCurrentSpace(displayUUID: target.displayUUID, spaceID: target.spaceID)
		}
		waitForDesktop(target.spaceID, required: needsSwitch) { [weak self] in
			guard let self else { return }
			if let error = self.accessibility.close(target) {
    self.refresh()
				self.setStatus(error, isError: true)
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
				guard let self else { return }
				let exists = self.accessibility.windowPresence(target)
				self.refresh()
    if let exists {
     self.setStatus(exists ? "已请求关闭；窗口仍存在，请检查保存提示或应用响应。".localized : "已关闭“\(target.ownerName)”的所选窗口。")
    } else { self.setStatus("已请求关闭，但无法读取窗口状态，尚不能确认关闭结果。".localized, isError: true) }
			}
		}
	}

	@objc private func focusPressed() {
		activateSelected(hideAfter: false)
	}

	private func activateSelected(hideAfter: Bool) {
  guard !bulkRunning, !loading else { return }
		guard let window = selectedWindow else {
			setStatus("请先选择一个窗口。".localized, isError: true)
			return
		}
		guard accessibility.isTrusted else {
			accessibility.requestAccess()
			setStatus("请先在系统设置中授予辅助功能权限，然后重试。".localized, isError: true)
			return
		}
		let needsSwitch = !window.isSticky && skyLight.spaces().first(where: { $0.id == window.spaceID })?.isCurrent == false
		if needsSwitch {
			skyLight.setCurrentSpace(displayUUID: window.displayUUID, spaceID: window.spaceID)
		}
		waitForDesktop(window.spaceID, required: needsSwitch) { [weak self] in
			guard let self else { return }
			if let error = self.accessibility.focus(window) {
				self.setStatus(error, isError: true)
			} else {
    self.verifyActivation(window, hideAfter: hideAfter)
			}
		}
	}

 private func verifyActivation(_ target: DesktopWindow, hideAfter: Bool, attempts: Int = 10) {
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
   guard let self else { return }
   let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
   let appVisible = NSRunningApplication(processIdentifier: target.pid)?.isHidden == false
   let minimized = self.accessibility.isMinimized(target) == true
   if frontmost && appVisible && !minimized && self.accessibility.focusedWindowID(pid: target.pid) == target.id {
    self.refresh()
    self.setStatus("已激活“\(target.ownerName)”中的窗口。")
    if hideAfter { self.window?.orderOut(nil); self.updateDockPresence() }
   } else if attempts > 0 {
    self.verifyActivation(target, hideAfter: hideAfter, attempts: attempts - 1)
   } else {
    self.setStatus("已请求激活，但未能确认目标窗口获得焦点，请重试。".localized, isError: true)
   }
  }
 }

	private func waitForDesktop(_ id: UInt64, required: Bool, attempts: Int = 60, onFailure: (() -> Void)? = nil, action: @escaping () -> Void) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
			guard let self else { return }
			if !required || self.skyLight.spaces().contains(where: { $0.id == id && $0.isCurrent }) {
				action()
			} else if attempts > 0 {
				self.waitForDesktop(id, required: true, attempts: attempts - 1, onFailure: onFailure, action: action)
			} else {
				self.setStatus("未能切换到目标桌面，请重试。".localized, isError: true)
    onFailure?()
			}
		}
	}

	@objc private func requestPermission() {
		if accessibility.requestAccess() {
			setStatus("辅助功能权限已授予。".localized)
		} else {
			accessibility.openAccessibilitySettings()
			setStatus("请启用本应用，然后返回并点击刷新。".localized, isError: true)
		}
		updateSummary()
	}

	@objc private func requestScreenRecording() {
		// Window titles come from CoreGraphics and require screen recording access.
		if CGRequestScreenCaptureAccess() {
			setStatus("屏幕录制权限已授予，正在刷新。".localized)
		} else {
			setStatus("请在系统设置中允许屏幕录制，然后重新启动本应用。".localized, isError: true)
		}
		updateSummary()
	}

	private func setStatus(_ text: String, isError: Bool = false) {
		statusLabel.stringValue = text
  statusLabel.toolTip = text
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
			let count = group.windows.isEmpty ? "无窗口".localized : "\(group.windows.count) 个窗口"
			let marker = group.space.isCurrent ? "● " : group.space.id == DesktopSpace.backgroundWindowsID ? "◐ " : ""
			let text = "\(marker) \(group.space.title)　\(count)"
			return labelCell(text: text, font: .systemFont(ofSize: 13, weight: .semibold), color: color)
		}

		guard let window = item as? DesktopWindow else { return nil }
		switch column {
		case "app":
			let state = window.backgroundStateDescription
			let name = window.ownerName + (window.isSticky ? "（所有桌面）".localized : "") + (state.isEmpty ? "" : " · " + state)
			return appCell(window: window, text: name)
		case "window":
			return labelCell(text: window.displayTitle, font: .systemFont(ofSize: 12), color: .labelColor)
		case "desktop":
			let title = window.hasKnownSpace ? spaceTitle(for: window.spaceID) : window.belongsToBackgroundSection ? "隐藏或最小化".localized : "未知桌面".localized
			let suffix = window.isSticky ? " · 所有桌面".localized : ""
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
