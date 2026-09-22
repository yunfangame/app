# 蜂窝加速器更新配置

客户端先从加密的 `ConFigOss4.json` 读取 `UpdateUrl`，再下载该地址对应的
`fengwoupdate.json`。正式客户端要求 `fengwoupdate.json` 同样使用 AES-GCM
加密并带 Ed25519 签名。

每个 `packages` 条目都是独立安装包：

- `enabled`：是否为该安装包启用更新检查。
- `version`：远程版本；只有高于客户端版本时才提示。
- `downloadUrl`：HTTPS 下载地址，也可以是相对于配置地址的路径。
- `title`：更新弹窗标题。
- `releaseNotesHtml`：弹窗展示的 HTML 更新说明。
- `publishedAt`：可选的 ISO 8601 发布时间。
- `sha256`：安装包 SHA-256。Windows 和 macOS 的软件内下载必须填写实际安装包的 64 位十六进制校验值；缺失或校验不匹配时不能安装。

桌面端仅在“高级设置 → 软件更新”提供检查、下载和安装入口。左上角版本号
只展示版本，“关于”中的旧检查入口及旧自动检查开关不再显示。
Windows 和 macOS 启动时静默检测新版，仅通过“高级设置”和“软件更新”的
红点提醒，不再自动弹出更新窗口。关闭更新窗口不会清除红点。

Windows 的 `downloadUrl` 指向 `.exe` 安装包，macOS 指向 `.pkg` 安装包。
下载期间显示百分比及文件大小；没有总大小时显示已下载大小。关闭弹窗后
继续后台下载，可从软件更新卡片重新查看。下载完成并通过 SHA-256 校验后，
用户点击“安装更新”打开系统安装程序。签名或重新打包后必须重新计算并更新
对应的 `sha256`。本地示例配置中的旧地址和空校验值需要在发布时替换。

包标识固定为：`android-arm64-v8a`、`android-armeabi-v7a`、
`android-x86_64`、`windows-x64`、`macos-arm64`、`macos-x64`。

修改 `fengwoupdate.source.json` 后运行 `加密更新配置.command`，上传生成的
`fengwoupdate.json`。若暂时不想升级某个平台，将对应的 `enabled` 改为
`false`；“不再提示”只忽略当前包的当前版本，新版本仍会提示。
