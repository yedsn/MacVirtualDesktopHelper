# MacVirtualDesktopHelper

原生 macOS 虚拟桌面助手。目标是迁移 WindowsVirtualDesktopHelper 的全部适用功能和交互，采用 macOS 视觉规范。当前是迁移基础，尚未完成全量迁移。

## 构建与运行

安装 Xcode Command Line Tools 后运行 `./build.sh`；使用 `./run.sh --show-overview` 构建并打开概览。产物为 `.build/MacVirtualDesktopHelper.app`。当前构建目标为 Apple Silicon、macOS 13+；已验证的来源原型运行环境为 macOS 27.2，最低部署版本不代表全部系统兼容。

使用独立 Bundle ID `local.macvirtualdesktophelper`，需要为新应用单独授予辅助功能和屏幕录制权限；来源原型的权限不作为新项目验证结果。编号直达依赖已启用的系统快捷键，不可用时回退相邻切换。

## 当前状态

已迁入菜单栏多图标、当前高亮、窗口概览、移动、激活、关闭的实现。搜索、卡片布局、拖拽、锁定清理、桌面规则、快照、备份及完整设置仍待实现。

功能对照见 [Feature-parity.md](Documentation/Feature-parity.md)，实施计划见 [OpenSpec 变更](openspec/changes/port-windows-feature-parity/proposal.md)。

原生 Space 创建、删除、重命名及导入时恢复结构暂不在范围内。缺失目标桌面必须报告，不能静默映射或创建。

## 来源与许可

源项目：相邻目录 WindowsVirtualDesktopHelper，基线提交 `6000fc6c4520526255afecd9ab6df5e2f852439f`，另包含本会话已验证但未提交的 MacPrototype 修复。来源验证记录保存在 Documentation，不能替代新应用独立验证。

沿用源项目 LICENSE.md，保留 Native/YABAI-LICENSE.txt。SkyLight 私有接口需逐系统版本验证。
