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
- `sha256`：可选的安装包 SHA256，预留给后续自动下载校验。

包标识固定为：`android-arm64-v8a`、`android-armeabi-v7a`、
`android-x86_64`、`windows-x64`、`macos-arm64`、`macos-x64`。

修改 `fengwoupdate.source.json` 后运行 `加密更新配置.command`，上传生成的
`fengwoupdate.json`。若暂时不想升级某个平台，将对应的 `enabled` 改为
`false`；“不再提示”只忽略当前包的当前版本，新版本仍会提示。
