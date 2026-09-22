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
- `sha256`：最终安装包的 SHA-256，软件内下载必须填写 64 位十六进制校验值；缺失或文件校验失败时不能安装。

安卓的更新入口统一为“我的 → 高级设置 → 软件更新”。启动时静默检测，
有新版时“高级设置”和“软件更新”显示红点，不再弹出旧的自动更新窗口。
“关于”中的旧检查入口和应用设置中的旧自动检查开关已隐藏。

安卓 `downloadUrl` 指向当前架构的 `.apk` 文件。下载显示百分比和大小，
支持取消、重试和关闭弹窗后继续下载；应用进程退出后的下载需要重新开始。
下载完成后核对 SHA-256，点击“安装更新”打开安卓系统安装程序。
若尚未允许此应用安装软件，会进入系统授权页；返回后点击“重试”继续，
无需重新下载；取消系统安装后同样可以重试。安装包必须与当前应用包名一致、签名兼容，且 `versionCode`
高于已安装版本。每次重新打包或签名后，须更新对应的 `sha256`。

包标识固定为：`android-arm64-v8a`、`android-armeabi-v7a`、
`android-x86_64`、`windows-x64`、`macos-arm64`、`macos-x64`。

修改 `fengwoupdate.source.json` 后运行 `加密更新配置.command`，上传生成的
`fengwoupdate.json`。若暂时不想升级某个平台，将对应的 `enabled` 改为
`false`；“不再提示”只忽略当前包的当前版本，新版本仍会提示。
