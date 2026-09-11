# Android v0.8.97 网络机制恢复测试记录

日期：2026-09-11

## 基线与隔离

- 基线分支：`app/main`
- 基线提交：`94e3d9ea2fe415d55670c30fc30636275bee9e23`
- 独立测试分支：`codex/android-upstream-0897-test`
- 独立工作树：`/Users/lilaibin/Documents/ChatGPT/vps/FlClash-v0.8.97-fengwo-android-test`
- FlClash 上游标签：`v0.8.97`（`db0388057962e83958dd355bc41fc22bfa1e901a`）
- mihomo/Core 子模块：`70f0570405c3c2c47bb113b88db95006d239b346`

原开发工作树、`app/main` 和生产环境均未被修改；本分支尚未合并、推送或部署。

## 改动边界

- 恢复 v0.8.97 的 Android 单进程 `LocalBinder` 服务生命周期，不使用 AIDL 或 `:remote` 服务。
- 恢复 Android JNI、VPN/TUN 文件描述符交接和 `VpnService.protect(fd)` 成功校验。
- Core 未接管 TUN 时立即失败并拆除 VPN，避免界面显示已连接但实际形成网络黑洞。
- 恢复上游的网络丢失、`onLosing` 延迟复查、DNS 更新及网络恢复处理。
- 保留蜂窝品牌、V2 登录/订阅、远程 API 配置、业务 UI、访问控制和现有数据结构。
- 保留 `app/main` 的桌面端 mixed listener 就绪检测，避免端口绑定失败时桌面端仍显示运行。

## 已完成验证

- Go：`go test ./...`、`go vet ./...`、`go test -race ./...`。
- Android：common/service/app 共 100 项测试通过，11 项与当前定制版不存在的非网络类有关并跳过，0 项失败。
- Flutter：`flutter analyze` 通过；网络、V2 登录、订阅、访问控制等目标测试 68 项通过。
- 全量 Flutter 测试中的 7 项失败已在同一 `app/main` 基线上复现，属于基线既有 UI 测试失败，不是本分支引入。
- Android API 36 arm64 模拟器完成冷安装、远程配置、V2 登录、V2 订阅同步和配置应用。
- 同一 AnyTLS 新加坡中转节点：规则模式与全局模式均通过 Google/Cloudflare 204 检测，出口国家为新加坡。
- VPN/TUN 被 Android 标记为 `CONNECTED` 且 `VALIDATED`，未发现 TUN、protect、Core 或 VpnService 致命异常。
- 数据网络断开期间请求按预期失败；恢复后 IP、DNS 和 HTTPS 自动恢复，VPN 仍有效并更新底层网络。
- 停止加速后 VPN 消失；再次启动后 VPN 和 HTTPS 均恢复。
- 61.7 MB arm64 Release 测试 APK 已完成升级安装、冷启动、在线 V2 登录、订阅同步、AnyTLS 启动和 HTTPS 204 复测；Android 将 VPN 标记为 `CONNECTED`、`VALIDATED`。
- v1.0.0 灰度 APK 已分别验证源密文、内置应急密文及 APK 内实际密文；均通过原密钥验签和解密。安装后 API 状态为 100%，V2 登录成功并同步 79 个节点、52592 字节配置。

## 测试包

- 文件：`dist/gray-1.0.0-20260911/蜂窝加速器-Android-v1.0.0-灰度-v0897网络修复-arm64-v8a.apk`
- 架构：`arm64-v8a`（适用于三星 S24 Ultra）
- 测试包名：`com.follow.clash.dev`，不会覆盖正式客户端
- 版本：`1.0.0`（versionCode `2026093101`）
- SHA-256：`8c01614505f5e8b7b0426224bde0343c58e7ef1a416e3cb2b87c249f321b718e`

## 回退方式

本次没有修改 `app/main`、没有部署后端，也没有改生产数据。停止测试时卸载测试包即可；代码层直接丢弃独立分支/工作树即可恢复到零改动状态。不要把本测试分支用于桌面端正式打包，除非完成相应平台的完整回归。
