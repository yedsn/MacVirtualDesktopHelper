# 本地构建与签名

在项目根目录执行 `./build.sh`，产物为 `.build/MacVirtualDesktopHelper.app`。脚本编译 Swift/AppKit 与 Native 桥接，复制 Info.plist 和两份许可后签名。当前只生成 Apple Silicon arm64 应用，部署目标 macOS 13；部署目标不代表私有接口已经在所有后续系统验证。实际验证记录见 Project-validation.md。

## 指定稳定签名身份

使用本机钥匙串已有的签名身份：

```sh
security find-identity -v -p codesigning
WVDH_SIGN_IDENTITY='你的签名身份名称' ./build.sh
codesign --verify --strict .build/MacVirtualDesktopHelper.app
```

未指定 WVDH_SIGN_IDENTITY 时，脚本使用找到的第一个代码签名身份；没有身份则使用临时签名，并输出提示。希望多次构建使用同一身份时应显式设置该变量。证书和私钥保留在本机钥匙串，不放入仓库。

保持 Bundle ID `local.macvirtualdesktophelper`、签名身份及运行路径稳定，有助于系统持续识别辅助功能和屏幕录制授权。临时签名下重建可能导致授权失效，需要在系统设置重新核对。实际读取或操作成功才证明权限有效。

本地开发使用上述脚本；安装包、GitHub/Gitee 发布与可选的签名公证流程见 [Release.md](Release.md)。应用没有内置自动更新。登录启动使用系统 SMAppService，需要将应用放在固定位置后实测注册；构建目录中的成功运行不证明登录项可用。

## 日志与许可

日志路径为 `~/Library/Logs/MacVirtualDesktopHelper/application.log`，应用菜单提供“查看日志”，在应用内只读窗口显示，每次打开重新加载。“关于”使用原生关于面板；“开源许可”在应用内显示打包的 LICENSE.md 和 YABAI-LICENSE.txt；“支持原作者”打开沿用 Windows 项目的支持链接。

应用包 Resources 中保留 LICENSE.md 和 YABAI-LICENSE.txt，后者对应 Native 桥接引用的上游实现。发布时应完整保留两份许可。
