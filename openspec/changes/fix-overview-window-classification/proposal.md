# Proposal

## Why

用户观察到概览中的非当前桌面主要只剩共享窗口，正常窗口被归入“隐藏或最小化”。代码把辅助功能查询未找到窗口也作为后台分组条件，混淆了桌面归属和操作能力；需要让概览准确展示每个桌面的窗口，并在实施时用临时窗口核实实际触发原因。

## What Changes

- 归属明确的普通窗口始终显示在对应桌面卡片，覆盖未激活桌面和被遮挡窗口；共享窗口在各所属桌面各显示一次。
- “隐藏或最小化”仅接收已确认最小化或所属应用已隐藏的窗口，不再由辅助功能查询失败触发归类。
- 辅助功能不可用或查询失败的窗口保留归属，显示“暂时无法操作”状态；执行动作时重新查询并报告真实结果。
- 归属不明窗口继续单独展示；切换桌面、重新采集时，不因可见性或查询成功与否发生错误分组。
- 将展示分组与规则候选、批量清理的资格判断分开，防止本次调整意外扩大自动操作范围。

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
