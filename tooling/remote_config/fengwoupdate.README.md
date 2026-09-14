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

当前客户端包标识为：`android-arm64-v8a`、`android-armeabi-v7a`、`android-x86`、
`android-x86_64`、`windows-arm64`、`windows-x86`、`windows-x64`、`macos-arm64`、
`macos-x64`、`linux-x64`。标识识别不代表已经提供所有平台的安装包。

Linux 首阶段仅提供 Ubuntu 22.04 / Debian 12 x64 的 DEB。配置键为 `linux-x64`，
不是文件名中的 `linux-amd64`；ARM 和其他 Linux 架构不匹配该条目。

## 生成与发布

仓库中的 `fengwoupdate.source.json` 是示例，不是线上配置的权威副本。发布时先获取并校验
当前线上配置，只合并需要变更的平台，保留其他平台及未知字段，避免回退已有版本和下载地址。
示例中的 Linux 条目默认关闭且没有下载地址；确认正式 HTTPS 地址和实际安装包哈希后才能开启。

使用与客户端相匹配的原密钥，在项目根目录运行以下命令。最后一个参数可指定受保护的现有
密钥文件；不要为了生成配置重新创建密钥，也不要上传密钥或明文配置。

```bash
dart run tooling/remote_config/remote_config_tool.dart seal tooling/remote_config/fengwoupdate.source.json tooling/remote_config/fengwoupdate.json /path/to/keys.json
dart run tooling/remote_config/remote_config_tool.dart verify tooling/remote_config/fengwoupdate.json /path/to/keys.json
```

先上传安装包并确认 HTTPS 下载可用，再上传生成的加密 `fengwoupdate.json` 至主配置
`UpdateUrl` 指定的位置。如果修改 `UpdateUrl`，主配置也必须重新加密签名后上传。
生成文件本身不会上传或发布任何配置。

若暂时不想升级某个平台，将对应的 `enabled` 改为 `false`；“不再提示”只忽略当前包的
当前版本，新版本仍会提示。手动检查不受忽略版本设置影响。

## Linux 更新边界

先前 `c575eb75` 及更早的 Linux 包没有平台识别，会跳过更新查询。已经安装这些包的用户
需要先手动覆盖安装包含该修复的新包；服务器配置无法给旧二进制补上更新能力。

保持 V1.0.2 重新构建时，远端同为 `1.0.2` 不会提示升级。后续发布需使用实际更高的版本，
并填写该构建对应的下载地址和 SHA256，不能仅提高配置版本却仍链接旧包。

“立即更新”只通过外部浏览器打开下载地址，不会自动下载校验或安装。`sha256` 目前仅为
预留元数据；用户仍需独立校验安装包并从托盘退出旧客户端后覆盖安装。
