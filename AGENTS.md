# Repository guidelines

- 产品范围见 Documentation/Feature-parity.md 与 OpenSpec 变更。兄弟 Windows 仓库只作为参考，不要修改。
- 使用 Swift/AppKit，系统私有接口集中在 SkyLightService 和 Native。
- 修改后运行 ./build.sh，重启本项目应用并验证菜单栏及概览。仅使用临时窗口验证移动、关闭与清理。
- 新 Bundle ID 单独核对辅助功能、事件发送及屏幕录制权限，不把请求发出当作成功。
- 桌面规则、清理锁定和快照使用版本化统一状态及原子替换；更新保留用户匹配字段，歧义不执行。
- 恢复快照只恢复规则。规则应用和批量清理须提供预览、移除候选、确认与结果。
- 暂不创建、删除或重命名原生 Space，缺失目标报告不可应用。
- 不提交构建产物、证书密钥、本地设置与个人窗口数据，保留上游许可。
