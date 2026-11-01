# Windows 设置迁移清单

来源：Windows SettingsForm.cs。所有适用设置均纳入迁移；下列条目仍需逐项核对实现与验收。

已核对的映射：`theme.icons.symbolFG.*` 对应 `menuSymbolForeground`，用于管理器四方块和前后导航符号；为空时跟随桌面图标颜色。设置使用原生颜色选择器，独立验证备份往返与非法颜色回滚。

此前仅提取 Get 调用遗漏了 Set/辅助方法中的设置：`general.language`、`feature.iconTray.desktopDisplayMode`、`feature.iconTray.windowManager`。后续验收须包含这些项目，不能以原始列表作为完整迁移证据。

- [ ] feature.showDesktopNameInIconTray
- [ ] feature.showDesktopStatusOverlay
- [ ] feature.showDesktopStatusOverlay.animate
- [ ] feature.showDesktopStatusOverlay.position
- [ ] feature.showDesktopStatusOverlay.showOnAllMonitors
- [ ] feature.showDesktopStatusOverlay.translucent
- [ ] feature.showDesktopSwitchOverlay
- [ ] feature.showDesktopSwitchOverlay.animate
- [ ] feature.showDesktopSwitchOverlay.duration
- [ ] feature.showDesktopSwitchOverlay.position
- [ ] feature.showDesktopSwitchOverlay.showOnAllMonitors
- [ ] feature.showDesktopSwitchOverlay.translucent
- [ ] feature.showPrevNextIcons
- [ ] feature.useHotKeyToJumpToDesktopNumber
- [ ] feature.useHotKeyToJumpToDesktopNumber.hotkey
- [ ] feature.useHotKeyToOpenTaskView
- [ ] general.startupWithWindows
- [ ] theme.icons.iconBG.
- [ ] theme.icons.iconFG.
- [ ] theme.icons.symbolFG.
