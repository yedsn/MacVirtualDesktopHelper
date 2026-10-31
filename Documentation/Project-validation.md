# 独立项目初始化验证

日期：2026-10-31；环境：macOS 27.2（26B123）。

- 独立目录 Git 已初始化，默认分支 main；尚未创建提交或配置远程。
- ./build.sh 编译及签名通过，产物为 .build/MacVirtualDesktopHelper.app。
- openspec validate port-windows-feature-parity --strict 通过。
- 标准 open 启动后，新进程 MacVirtualDesktopHelper 正常响应，概览标题与新应用名称一致。
- 菜单栏显示 5 个桌面及概览入口，当前桌面高亮可读。
- 新应用辅助功能未授权、窗口标题不可用；未将来源应用的权限和窗口操作验证转记为本项目通过。需要用户在系统设置为新应用授权，再独立验证桌面切换及窗口操作。
- 为避免重复菜单栏图标，已停止旧 WVDHMacPrototype，只启动新项目应用。
- 当前完成初始化与迁移计划，完整功能迁移仍按 tasks.md 推进。
