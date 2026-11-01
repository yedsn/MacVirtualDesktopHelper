import AppKit
import ServiceManagement

private final class ColorSelectionAction: NSObject {
 let changed: () -> Void
 init(_ changed: @escaping () -> Void) { self.changed = changed }
 @objc func apply(_ sender: NSColorWell) { changed() }
}

private final class ShortcutPresetAction: NSObject {
 let applyPreset: () -> Void
 init(_ applyPreset: @escaping () -> Void) { self.applyPreset = applyPreset }
 @objc func apply(_ sender: NSButton) { applyPreset() }
}

private final class SettingsDocumentView: NSView {
 override var isFlipped: Bool { true }
}

final class SettingsController: NSWindowController {
 private let store: RuleStore
 private let theme = NSPopUpButton()
 private let language = NSPopUpButton()
 private let mode = NSPopUpButton()
 private let manager = NSPopUpButton()
 private let login = NSButton(checkboxWithTitle: "登录时启动".localized, target: nil, action: nil)
 private let loginStatus = NSTextField(labelWithString: "")
 private let hideBounds = NSButton(checkboxWithTitle: "在首尾桌面隐藏不可用的导航按钮".localized, target: nil, action: nil)
 private let restoreFocus = NSButton(checkboxWithTitle: "切换后恢复目标桌面上次窗口焦点".localized, target: nil, action: nil)
 private let dockIcon = NSButton(checkboxWithTitle: "主窗口打开时在 Dock 显示图标".localized, target: nil, action: nil)
 private let glass = NSButton(checkboxWithTitle: "启用主窗口毛玻璃背景".localized, target: nil, action: nil)
 private let overviewSize = NSPopUpButton()
 private let iconSpacing = NSTextField(string: "8")
 private let nameInitial = NSButton(checkboxWithTitle: "导航模式显示桌面名称首字".localized, target: nil, action: nil)
 var changed: (() -> Void)?
 var openSnapshots: (() -> Void)?
 var exportConfiguration: (() -> Void)?
 var importConfiguration: (() -> Void)?
 init(store: RuleStore) {
  self.store = store
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
  window.title = "设置".localized; window.isReleasedWhenClosed = false
  super.init(window: window)
  theme.addItems(withTitles: ["跟随系统".localized, "浅色".localized, "深色".localized])
  language.addItems(withTitles: ["简体中文", "English"])
  mode.addItems(withTitles: ["全部桌面（合并菜单栏控件）".localized, "前一个 / 当前 / 后一个".localized])
  manager.addItems(withTitles: ["内置所有窗口".localized, "系统 Mission Control".localized])
  let save = NSButton(title: "保存".localized, target: self, action: #selector(saveSettings))
  let hotkeys = NSButton(title: "全局快捷键…".localized, target: self, action: #selector(editHotKeys))
  let overlay = NSButton(title: "桌面浮层…".localized, target: self, action: #selector(editOverlay))
  let appearance = NSButton(title: "菜单栏图标外观…".localized, target: self, action: #selector(editMenuAppearance))
  let backupActions = NSStackView(views: [NSButton(title: "规则快照…".localized, target: self, action: #selector(showSnapshots)), NSButton(title: "导出配置…".localized, target: self, action: #selector(exportSettings)), NSButton(title: "导入配置…".localized, target: self, action: #selector(importSettings))])
  backupActions.spacing = 8
  login.target = self; login.action = #selector(toggleLogin)
  window.setContentSize(NSSize(width: 620, height: 680))
  overviewSize.addItems(withTitles: (11...20).map { String($0) + " 点".localized })
  iconSpacing.widthAnchor.constraint(equalToConstant: 100).isActive = true
  func section(_ title: String, _ views: [NSView]) -> NSView {
   let label = NSTextField(labelWithString: title)
   label.font = .systemFont(ofSize: 14, weight: .semibold)
   let group = NSStackView(views: [label] + views)
   group.orientation = .vertical; group.alignment = .leading; group.spacing = 9
   return group
  }
  func row(_ title: String, _ control: NSView) -> NSView {
   let label = NSTextField(labelWithString: title)
   label.textColor = .secondaryLabelColor
   label.widthAnchor.constraint(equalToConstant: 110).isActive = true
   let row = NSStackView(views: [label, control])
   row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
   return row
  }
  let stack = NSStackView(views: [
   section("窗口与外观".localized, [row("语言（重启后生效）".localized, language), row("主题".localized, theme), row("概览文字大小".localized, overviewSize), dockIcon, glass]),
   section("菜单栏".localized, [row("显示方式".localized, mode), row("间距（0–24 点）".localized, iconSpacing), appearance, nameInitial, hideBounds]),
   section("操作与启动".localized, [row("窗口管理器".localized, manager), restoreFocus, NSStackView(views: [hotkeys, overlay]), login, loginStatus]),
   section("配置与规则".localized, [backupActions])
  ])
  stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 24
  let scroll = NSScrollView()
  scroll.hasVerticalScroller = true; scroll.drawsBackground = false
  let document = SettingsDocumentView(frame: NSRect(x: 0, y: 0, width: 600, height: 900))
  stack.translatesAutoresizingMaskIntoConstraints = false
  document.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -24)])
  document.layoutSubtreeIfNeeded()
  document.setFrameSize(NSSize(width: 600, height: stack.fittingSize.height + 40))
  scroll.documentView = document
  if let content = window.contentView {
   scroll.translatesAutoresizingMaskIntoConstraints = false
   save.translatesAutoresizingMaskIntoConstraints = false
   content.addSubview(scroll); content.addSubview(save)
   NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -12), save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
  }
  reload()
 }
 required init?(coder: NSCoder) { fatalError() }
 @objc private func showSnapshots() { openSnapshots?() }
 @objc private func exportSettings() { exportConfiguration?() }
 @objc private func importSettings() { importConfiguration?() }
 @objc private func editMenuAppearance() {
  let foreground = NSColorWell()
  let symbols = NSColorWell()
  symbols.color = CompactStatusView.color(store.state.settings?.menuSymbolForeground) ?? CompactStatusView.color(store.state.settings?.menuForeground) ?? .white
  symbols.setAccessibilityLabel("管理器与导航符号颜色".localized)
  let sameSymbols = NSButton(checkboxWithTitle: "管理器与导航符号跟随桌面图标颜色".localized, target: nil, action: nil)
  sameSymbols.state = store.state.settings?.menuSymbolForeground == nil ? .on : .off
  let symbolAction = ColorSelectionAction { sameSymbols.state = .off }
  symbols.target = symbolAction; symbols.action = #selector(ColorSelectionAction.apply(_:))
  let background = NSColorWell()
  foreground.color = CompactStatusView.color(store.state.settings?.menuForeground) ?? .white
  background.color = CompactStatusView.color(store.state.settings?.menuBackground) ?? .darkGray
  foreground.setAccessibilityLabel("图标与文字颜色".localized)
  background.setAccessibilityLabel("整体背景颜色".localized)
  let automatic = NSButton(checkboxWithTitle: "图标颜色跟随菜单栏".localized, target: nil, action: nil)
  let transparent = NSButton(checkboxWithTitle: "整体背景透明".localized, target: nil, action: nil)
  automatic.state = store.state.settings?.menuForeground == nil ? .on : .off
  transparent.state = store.state.settings?.menuBackground == nil ? .on : .off
  let foregroundAction = ColorSelectionAction { automatic.state = .off }
  let backgroundAction = ColorSelectionAction { transparent.state = .off }
  foreground.target = foregroundAction; foreground.action = #selector(ColorSelectionAction.apply(_:))
  background.target = backgroundAction; background.action = #selector(ColorSelectionAction.apply(_:))
  let colorPanel = NSColorPanel.shared
  let previousModal = colorPanel.worksWhenModal
  let previousAlpha = colorPanel.showsAlpha
  colorPanel.worksWhenModal = true
  colorPanel.showsAlpha = false
  let font = NSPopUpButton()
  font.addItem(withTitle: "系统默认".localized)
  let fontNames = NSFontManager.shared.availableFonts.sorted()
  font.addItems(withTitles: fontNames)
  if let name = store.state.settings?.menuFontName, let index = fontNames.firstIndex(of: name) { font.selectItem(at: index + 1) }
  let size = NSTextField(string: String(store.state.settings?.menuFontSize ?? 11))
  let stack = NSStackView(views: [automatic, NSTextField(labelWithString: "自定义图标与文字颜色".localized), foreground, transparent, NSTextField(labelWithString: "自定义整体背景颜色".localized), background])
  stack.orientation = .vertical; stack.alignment = .leading
  stack.addArrangedSubview(sameSymbols)
  stack.addArrangedSubview(symbols)
  stack.addArrangedSubview(NSTextField(labelWithString: "编号字体".localized))
  stack.addArrangedSubview(font)
  stack.addArrangedSubview(NSTextField(labelWithString: "字号（8–16 点）".localized))
  stack.addArrangedSubview(size)
  font.widthAnchor.constraint(equalToConstant: 380).isActive = true
  size.widthAnchor.constraint(equalToConstant: 100).isActive = true
  stack.frame = NSRect(x: 0, y: 0, width: 380, height: 415)
  for well in [foreground, background, symbols] {
   well.widthAnchor.constraint(equalToConstant: 80).isActive = true
   well.heightAnchor.constraint(equalToConstant: 28).isActive = true
  }
  let alert = NSAlert(); alert.messageText = "菜单栏图标外观".localized; alert.accessoryView = stack
  alert.addButton(withTitle: "保存".localized); alert.addButton(withTitle: "取消".localized)
  let response = withExtendedLifetime((foregroundAction, backgroundAction, symbolAction)) { alert.runModal() }
  foreground.deactivate(); background.deactivate(); symbols.deactivate()
  NSColorPanel.shared.orderOut(nil)
  colorPanel.worksWhenModal = previousModal
  colorPanel.showsAlpha = previousAlpha
  guard response == .alertFirstButtonReturn else { return }
  guard let fontSize = Double(size.stringValue), fontSize.isFinite, (8...16).contains(fontSize) else {
   let error = NSAlert(); error.messageText = "字号须为 8–16 点".localized; error.runModal(); return
  }
  do {
   try store.update { state in
    var settings = state.settings ?? ApplicationSettings()
    settings.menuForeground = automatic.state == .on ? nil : colorHex(foreground.color)
    settings.menuSymbolForeground = sameSymbols.state == .on ? nil : colorHex(symbols.color)
    settings.menuBackground = transparent.state == .on ? nil : colorHex(background.color)
    settings.menuFontName = font.indexOfSelectedItem == 0 ? nil : font.titleOfSelectedItem
    settings.menuFontSize = fontSize
    state.settings = settings
   }
   changed?()
  } catch { NSAlert(error: error).runModal() }
 }
 private func colorHex(_ color: NSColor) -> String {
  let rgb = color.usingColorSpace(.sRGB) ?? .white
  return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
 }
 func reload() {
  let settings = store.state.settings ?? ApplicationSettings()
  theme.selectItem(at: ["auto", "light", "dark"].firstIndex(of: settings.theme) ?? 0)
  language.selectItem(at: settings.language == "en" ? 1 : 0)
  mode.selectItem(at: settings.desktopDisplayMode == "navigation" ? 1 : 0)
  manager.selectItem(at: settings.windowManager == "system" ? 1 : 0)
  hideBounds.state = settings.hideNavigationAtBounds ? .on : .off
  restoreFocus.state = settings.restoreWindowFocus == true ? .on : .off
  iconSpacing.stringValue = String(settings.menuIconSpacing ?? 8)
  dockIcon.state = (settings.showDockIcon ?? true) ? .on : .off
  glass.state = (settings.frostedWindow ?? true) ? .on : .off
  nameInitial.state = settings.showDesktopNameInitial == true ? .on : .off
  overviewSize.selectItem(at: Int(settings.overviewFontSize ?? 14) - 11)
  updateLoginStatus()
 }
 private func updateLoginStatus() {
  let status = SMAppService.mainApp.status
  login.state = status == .enabled ? .on : .off
  switch status {
  case .enabled: loginStatus.stringValue = "登录项已启用".localized
  case .requiresApproval: loginStatus.stringValue = "等待系统批准，请在登录项设置中启用".localized
  case .notFound: loginStatus.stringValue = "系统未找到应用，请将应用安装到固定位置后重试".localized
  default: loginStatus.stringValue = "登录项未启用".localized
  }
 }
 @objc private func toggleLogin() {
  do {
   if login.state == .on { try SMAppService.mainApp.register() }
   else { try SMAppService.mainApp.unregister() }
   updateLoginStatus()
   if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
  } catch { updateLoginStatus(); NSAlert(error: error).runModal() }
 }
 @objc private func saveSettings() {
  var settings = store.state.settings ?? ApplicationSettings()
  guard let spacing = Double(iconSpacing.stringValue), spacing.isFinite, (0...24).contains(spacing) else {
   let alert = NSAlert(); alert.messageText = "图标间距须为 0–24 点".localized; alert.runModal(); return
  }
  settings.showDockIcon = dockIcon.state == .on
  settings.frostedWindow = glass.state == .on
  settings.showDesktopNameInitial = nameInitial.state == .on
  settings.overviewFontSize = Double(overviewSize.indexOfSelectedItem + 11)
  settings.menuIconSpacing = spacing
  settings.theme = ["auto", "light", "dark"][theme.indexOfSelectedItem]
  settings.language = language.indexOfSelectedItem == 1 ? "en" : "zh-CN"
  settings.desktopDisplayMode = mode.indexOfSelectedItem == 1 ? "navigation" : "all-desktops"
  settings.windowManager = manager.indexOfSelectedItem == 1 ? "system" : "built-in"
  settings.hideNavigationAtBounds = hideBounds.state == .on
  settings.restoreWindowFocus = restoreFocus.state == .on
  do { try store.update { $0.settings = settings }; changed?() } catch { NSAlert(error: error).runModal() }
 }
 @objc private func editHotKeys() {
  let alert = NSAlert(); alert.messageText = "全局快捷键".localized
  alert.informativeText = "每行：动作=修饰键+按键。例如 manager=Option+D，forward=Option+Right，backward=Option+Left，previous=Option+`，desktop:1=Option+1。留空禁用。保存后报告系统注册冲突。".localized
  let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 230))
  editor.isRichText = false
  editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
  editor.string = HotKeyText.render(store.state.settings?.hotKeys ?? [])
  let preset = NSPopUpButton()
  preset.addItems(withTitles: ["Option + 数字".localized, "Option + Shift + 数字".localized, "Control + 数字".localized, "Control + Option + 数字".localized, "禁用桌面数字快捷键".localized])
  let apply = NSButton(title: "应用到桌面 1–9".localized, target: nil, action: nil)
  let presetAction = ShortcutPresetAction {
   let remaining = editor.string.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("desktop:") }
   let modifiers = ["Option", "Option+Shift", "Control", "Control+Option"]
   var desktopLines: [String] = []
   if modifiers.indices.contains(preset.indexOfSelectedItem) {
    let modifier = modifiers[preset.indexOfSelectedItem]
    for number in 1...9 { desktopLines.append("desktop:\(number)=\(modifier)+\(number)") }
   }
   editor.string = (remaining.filter { !$0.isEmpty } + desktopLines).joined(separator: "\n")
  }
  apply.target = presetAction; apply.action = #selector(ShortcutPresetAction.apply(_:))
  let presetRow = NSStackView(views: [preset, apply]); presetRow.spacing = 8
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 230))
  scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
  editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]
  scroll.documentView = editor
  let stack = NSStackView(views: [presetRow, scroll])
  stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
  scroll.widthAnchor.constraint(equalToConstant: 500).isActive = true
  scroll.heightAnchor.constraint(equalToConstant: 230).isActive = true
  stack.frame = NSRect(x: 0, y: 0, width: 500, height: 275)
  alert.accessoryView = stack; alert.addButton(withTitle: "保存".localized); alert.addButton(withTitle: "取消".localized)
  while true {
   let response = withExtendedLifetime(presetAction) { alert.runModal() }
   guard response == .alertFirstButtonReturn else { return }
   do {
    let bindings = try HotKeyText.parse(editor.string)
    try store.update { state in var settings = state.settings ?? ApplicationSettings(); settings.hotKeys = bindings; state.settings = settings }
    changed?()
    return
   } catch {
    NSAlert(error: error).runModal()
    // Keep the original editor and preset action alive so corrections do not
    // discard the shortcut configuration the user has just entered.
   }
  }
 }
 private func hotKeyError() -> NSError { NSError(domain: "HotKeys", code: 1, userInfo: [NSLocalizedDescriptionKey: "快捷键格式无效或按键重复，请按示例填写。".localized]) }
 @objc private func editOverlay() {
  let settings = store.state.settings?.overlay ?? OverlaySettings()
  let showSwitch = NSButton(checkboxWithTitle: "切换桌面时显示提示".localized, target: nil, action: nil)
  let showStatus = NSButton(checkboxWithTitle: "常驻显示当前桌面".localized, target: nil, action: nil)
  let allDisplays = NSButton(checkboxWithTitle: "所有显示器".localized, target: nil, action: nil)
  let translucent = NSButton(checkboxWithTitle: "半透明".localized, target: nil, action: nil)
  let animate = NSButton(checkboxWithTitle: "动画".localized, target: nil, action: nil)
  for (button, enabled) in [(showSwitch, settings.showSwitch), (showStatus, settings.showStatus), (allDisplays, settings.allDisplays), (translucent, settings.translucent), (animate, settings.animate)] { button.state = enabled ? .on : .off }
  let duration = NSTextField(string: String(settings.duration))
  let labels = ["左上".localized, "中上".localized, "右上".localized, "左中".localized, "居中".localized, "右中".localized, "左下".localized, "中下".localized, "右下".localized]
  let position = NSPopUpButton(); position.addItems(withTitles: labels)
  let legacy = ["center": "middlecenter", "top": "topcenter", "bottom": "bottomcenter"]
  position.selectItem(at: OverlaySettings.positions.firstIndex(of: legacy[settings.position] ?? settings.position) ?? 4)
  let statusPosition = NSPopUpButton(); statusPosition.addItems(withTitles: labels)
  statusPosition.selectItem(at: OverlaySettings.positions.firstIndex(of: settings.statusPosition ?? "topcenter") ?? 1)
  let statusScreens = NSButton(checkboxWithTitle: "常驻浮层：所有显示器".localized, target: nil, action: nil)
  let statusTranslucent = NSButton(checkboxWithTitle: "常驻浮层：半透明".localized, target: nil, action: nil)
  let statusAnimate = NSButton(checkboxWithTitle: "常驻浮层：动画".localized, target: nil, action: nil)
  for (button, enabled) in [(statusScreens, settings.statusAllDisplays ?? settings.allDisplays), (statusTranslucent, settings.statusTranslucent ?? settings.translucent), (statusAnimate, settings.statusAnimate ?? settings.animate)] { button.state = enabled ? .on : .off }
  let stack = NSStackView(views: [showSwitch, showStatus, allDisplays, translucent, animate, NSTextField(labelWithString: "提示秒数（0 为持续显示）".localized), duration, position, NSTextField(labelWithString: "常驻浮层位置".localized), statusPosition, statusScreens, statusTranslucent, statusAnimate])
  stack.orientation = .vertical; stack.alignment = .leading; stack.frame = NSRect(x: 0, y: 0, width: 400, height: 450)
  let alert = NSAlert(); alert.messageText = "桌面浮层".localized; alert.accessoryView = stack
  alert.addButton(withTitle: "保存".localized); alert.addButton(withTitle: "取消".localized)
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  guard let seconds = Double(duration.stringValue) else { NSAlert(error: hotKeyError()).runModal(); return }
  do {
   try store.update { state in
    var application = state.settings ?? ApplicationSettings()
    application.overlay = OverlaySettings(showSwitch: showSwitch.state == .on, showStatus: showStatus.state == .on, duration: seconds, position: OverlaySettings.positions[position.indexOfSelectedItem], allDisplays: allDisplays.state == .on, translucent: translucent.state == .on, animate: animate.state == .on)
    application.overlay?.statusPosition = OverlaySettings.positions[statusPosition.indexOfSelectedItem]
    application.overlay?.statusAllDisplays = statusScreens.state == .on
    application.overlay?.statusTranslucent = statusTranslucent.state == .on
    application.overlay?.statusAnimate = statusAnimate.state == .on
    state.settings = application
   }
   changed?()
  } catch { NSAlert(error: error).runModal() }
 }
}
