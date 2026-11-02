# Proposal

## Why

用户需要在当前虚拟桌面的多个应用窗口之间快速选择，现有桌面快捷键和完整概览无法提供按住 Option、连续按 Tab、松键切换的交互。新增独立窗口切换器，使同一应用的多个窗口也可直接选择，并避免切到其他桌面。

## What Changes

- 设置增加“当前桌面窗口切换”开关及快捷键录入，默认组合为 Option + Tab，支持禁用和冲突反馈。
- 展示当前普通桌面的全部可识别应用窗口，包含当前窗口、被遮挡窗口，以及归属明确的最小化和隐藏窗口；同一应用按窗口分别列出。
- 使用图标、应用名和窗口标题展示候选；按最近使用顺序排列，按住修饰键时 Tab 循环选择，Shift + Tab 反向选择，松开保持修饰键后才激活，Esc 取消。
- 增加快速按放、事件丢失、权限不足、目标关闭和桌面变化的处理；激活前重验窗口归属，激活后验证实际焦点。
- 第一版支持普通桌面；多屏按焦点窗口所在屏幕确定当前桌面，无焦点时按鼠标所在屏幕确定。全屏独立 Space 明确显示暂不支持，不回退到其他桌面。

## Capabilities

### New Capabilities
- `current-desktop-window-switcher`: 当前桌面窗口候选、按住选择与松键激活、快捷键设置、权限及异常处理。

### Modified Capabilities

无。保留现有概览对隐藏和最小化窗口的独立分组行为；新切换器使用原始窗口归属。

## Impact

- 涉及 AppDelegate、GlobalHotKeys、HotKeyText、SettingsController、ApplicationSettings/RuleStore、WindowCatalog、AccessibilityWindowService，新增独立切换会话和 AppKit 面板。
- Space 识别及必要私有激活接口集中在 SkyLightService 和 Native；不修改原生桌面结构，不移动窗口。
- 沿用版本化配置与原子保存，兼容旧配置，不持久化窗口标题、窗口列表或使用历史。无需新增第三方依赖。
- 补充自动化状态测试、真实按键与焦点验收，以及 Documentation/Feature-parity.md 的实际支持范围。
