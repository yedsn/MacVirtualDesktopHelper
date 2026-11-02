# Proposal

## Why

用户观察到概览中的非当前桌面主要只剩共享窗口，正常窗口被归入“隐藏或最小化”。代码把辅助功能查询未找到窗口也作为后台分组条件，混淆了桌面归属和操作能力；需要让概览准确展示每个桌面的窗口，并在实施时用临时窗口核实实际触发原因。

## What Changes

- 当前桌面概览以 Option + Tab 候选为准；其他桌面普通应用窗口在成员明确且无非标准证据时提前展示，避免 AX 当前桌面限制导致漏项。
- 符合条件的隐藏/最小化窗口保留所属桌面，与切换器集合一致。
- 被排除的特殊应用窗口及未知归属窗口集中到末尾“其他窗口”，按身份去重，不直接丢弃。
- 其他窗口不能作为拖放目标，不自动扩大规则及清理范围；单窗口操作可以重试。

## Capabilities

### New Capabilities

- `window-overview`: 按真实桌面归属展示窗口，区分隐藏、最小化、操作能力未知和归属未知，并保持操作安全边界。当前 openspec/specs 尚无已归档能力，本能力承接在途迁移变更中的概览细则。

### Modified Capabilities

无已归档能力需要修改。与在途 port-windows-feature-parity 的隐藏/最小化要求兼容；实现时同步行为说明，不修改当前桌面切换器的独立候选契约。

## Impact

- WindowCatalog、AccessibilityWindowService：辅助功能查询结果、最小化状态证据和桌面成员采集。
- Models、OverviewWindowController、DesktopCardView、Localization：分组、状态提示和操作资格判断。
- WindowSnapshotTests 及相关窗口操作测试：非当前桌面、读取失败、共享窗口和操作边界回归。
- Documentation/Feature-parity.md：记录实际验收结果。无新增依赖或持久化格式迁移，不涉及原生 Space 结构操作。
