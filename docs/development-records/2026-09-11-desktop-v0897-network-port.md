# 2026-09-11 桌面端 v0.8.97 网络机制移植

## 基线与分支

- 基线：`app/main@94e3d9ea2fe415d55670c30fc30636275bee9e23`
- 本地集成分支：`codex/desktop-upstream-0897-port`
- 本次未修改或推送 `app/main`，未生成正式桌面安装包。

## 提交记录

- `ad270e8`：将共享 Core 包装层和 Clash.Meta 对齐至已在 Android 验证的 v0.8.97 网络实现。
- `bad5276`：增强 Windows Core/IPC 恢复、系统代理写入保护和退出清理。
- `60a5021`：增强 macOS DNS 持久恢复、网络切换/唤醒重同步和 Core 启动路径处理。

## 保留范围

- 保留现有 V2 登录和订阅解密链路。
- 保留远程配置主备入口、加密缓存和应急配置。
- 保留链式代理、业务 UI、更新、签名及打包逻辑。
- 保留单 Core 进程保护，避免重复启动内核。

## 验证记录

- Flutter 桌面/Core/V2/远程配置/链式代理联合测试：401 项通过。
- 构建密钥测试：18 项通过。
- Core 补丁工具测试：41 项通过。
- `flutter analyze --no-fatal-infos`：通过，0 个问题。
- Go Core 在 `CGO_ENABLED=0` 和 `CGO_ENABLED=1` 下的 `go test`、`go vet`：全部通过。
- macOS Debug 原生构建、应用签名校验：通过。
- 正式配置和 APK 应急配置使用既有密钥完成 Ed25519 验签及 AES-256-GCM 解密验证。
- 七牛与阿里云远程配置内容一致，均通过既有密钥验证。

## 发布前剩余验证

- Windows 原生 C++ 插件、注册表代理写入/回读、`WM_ENDSESSION` 清理需在 Windows Runner 或真实 Windows 机器验证。
- 正式打包时必须通过现有构建脚本注入 AES 密钥和 Ed25519 公钥，并在成品安装包上再次执行解密及真实登录测试。

## 回滚说明

- 当前 `app/main` 未变化，放弃此集成分支即可完整回到原版本。
- 若以后将三个提交合并到 `app/main`，应按 `60a5021`、`bad5276`、`ad270e8` 的逆序分别执行 `git revert`，再运行相同测试；不需要数据库回滚。
