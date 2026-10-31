## Why

Mac 系统能力原型已在 macOS 27.2 验证。现在建立独立项目，逐项迁移 Windows 版功能和交互，以原生 Mac 视觉实现完整产品。

## What Changes

- 独立 Git 仓库、应用身份和构建入口，迁入已验证系统桥接与原型功能。
- 按 Documentation/Feature-parity.md 迁移菜单栏、桌面卡片概览、键盘/拖拽、清理保护、批量清理、全局规则、规则快照、备份、快捷键、浮层及设置。
- 保持预览、排除、确认、执行和结果流程。恢复快照不移动窗口。
- 暂不实现原生 Space 创建、删除、重命名及导入恢复结构。

## Capabilities

### New Capabilities
- mac-feature-parity: Windows 功能和交互的原生 Mac 迁移。

## Impact

仅修改独立 MacVirtualDesktopHelper 项目。Swift/AppKit 和隔离的 Objective-C 系统桥接；本地 Application Support 持久化，不依赖 Windows 运行时。完整迁移尚未完成。
