# 发布流程

发布通过 Git 标签触发 GitHub Actions：本地脚本升级版本并打 `vX.Y.Z` 标签，Actions 在 macOS Runner 上分别构建 Apple Silicon 与 Intel 应用，生成 DMG、ZIP 和校验和，创建 GitHub Release；启用后由自托管 Runner 把同样一组文件镜像到 Gitee 的 `latest` Release。

```text
scripts/release/release.sh
  -> 修改 Resources/Info.plist 版本
  -> 运行 Tests/run.sh 与 build.sh
  -> commit "release: vX.Y.Z"、创建 vX.Y.Z 标签
  -> push（--push）
  -> .github/workflows/release.yml
  -> GitHub Release：arm64 / x86_64 的 dmg、zip、SHA256SUMS
  -> 可选：Gitee latest 镜像
```

应用是 Swift/AppKit 原生程序，不使用 Tauri，因此不生成 `latest.json`，也没有内置自动更新。升级方式是下载新版本替换 `/Applications` 中的旧应用；辅助功能与屏幕录制授权在 Bundle ID、签名身份和安装路径保持不变时通常可以延续，重建后需要重新核对实际权限是否生效。

## 本地发布

```sh
./scripts/release/release.sh 0.1.0          # 指定版本，只提交和打标签
./scripts/release/release.sh 0.1.0 --push  # 同时推送分支与标签，触发 Actions
./scripts/release/release.sh                # 交互输入版本号，默认建议下一个补丁版本
```

从 VS Code 的 release 入口运行时，会先显示当前版本、询问发布版本号，再确认是否继续；输入 q 或在确认处回车可取消。未提供版本号的非交互调用会退出。脚本会 `git add -A`，因此发布前请先提交或暂存与本次发布无关的改动。`Resources/Info.plist` 中的 `CFBundleShortVersionString` 写入版本号，`CFBundleVersion` 写入 `major*10000 + minor*100 + patch` 形式的递增构建号。

只想在本地产出安装包时：

```sh
./scripts/release/package.sh arm64
./scripts/release/package.sh x86_64
```

产物写入 `dist/`，命名为 `MacVirtualDesktopHelper_<version>_<arch>.dmg`、同名 `.zip`，以及按架构分开的 `SHA256SUMS.<arch>`；CI 发布时会合并为单个 `SHA256SUMS`。

## 签名与公证

不配置任何密钥时，构建使用 ad-hoc 签名，产物可以运行，但下载后需要用户手动允许打开，且每次重建可能丢失系统授权。配置下列仓库 Secrets 后，CI 会用 Developer ID Application 证书签名并对 DMG 做公证和装订：

- `APPLE_CERTIFICATE_P12`：Developer ID Application 证书的 base64 编码 `.p12`。
- `APPLE_CERTIFICATE_PASSWORD`：该 `.p12` 的密码。
- `APPLE_ID`：Apple 开发者账号邮箱。
- `APPLE_TEAM_ID`：开发者团队 ID。
- `APPLE_APP_PASSWORD`：用于公证的 App 专用密码。

缺少后三项时只签名、不公证。证书与私钥只放在 GitHub Secrets，不要提交到仓库。

## Gitee 镜像

同步任务默认关闭，按仓库变量开启：

- 变量 `ENABLE_GITEE_SYNC=true`：启用 `sync-gitee` 任务。
- Secret `GITEE_ACCESS_TOKEN`：Gitee 私人令牌，需要仓库 Release 读写权限。
- 变量 `GITEE_SYNC_PROXY`（可选）：自托管 Runner 访问 GitHub 使用的代理地址，例如 `http://192.168.1.10:7890`；留空则沿用 Runner 自身网络设置。该值必须可从 Runner 主机访问。
- 自托管 Runner 标签需为 `self-hosted`、`linux`、`x64`、`gitee-sync`。

同步脚本从 GitHub Release 下载全部资产，重命名为去掉版本号的稳定文件名（`MacVirtualDesktopHelper_arm64.dmg`、`MacVirtualDesktopHelper_x86_64.dmg` 等），覆盖 Gitee `latest` Release 的附件。缺少任一架构 DMG 或 `SHA256SUMS` 时脚本会报错退出，不会留下不完整的镜像。

Gitee 目标仓库：https://gitee.com/hongxiaojian/MacVirtualDesktopHelper；创建 latest Release 使用 main 分支。代理变量为空时沿用 Runner 自身网络设置。

## GitHub 侧配置

1. `Settings -> Actions -> General`：启用 Actions；工作流已声明 `contents: write`，如组织策略限制写入，需要允许工作流创建 Release。
2. `Settings -> Secrets and variables -> Actions -> Secrets`：按需添加签名、公证和 `GITEE_ACCESS_TOKEN`。
3. `Settings -> Secrets and variables -> Actions -> Variables`：`ENABLE_GITEE_SYNC`，可选 `GITEE_SYNC_PROXY`。
4. `Settings -> Actions -> Runners`：启用 Gitee 镜像时，确保自托管 Runner 在线且标签与工作流一致。
5. 推送 `v*` 标签或执行发布脚本触发构建。

## 发布后核对

- Release 中存在两个架构的 DMG、ZIP 与 `SHA256SUMS`，且校验和能通过 `shasum -a 256 -c`。
- 在 Apple Silicon 与 Intel 设备上分别挂载 DMG、拖入 `/Applications` 并启动，确认菜单栏图标、概览窗口正常。
- 新 Bundle 首次运行后重新核对辅助功能与屏幕录制权限，实际移动或关闭窗口成功才算权限可用。
- 启用 Gitee 时，`https://gitee.com/hongxiaojian/MacVirtualDesktopHelper/releases/tag/latest` 中的附件齐全，文件名不带版本号。
