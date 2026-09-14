# 2026-09-14 Linux 上游升级集成

本文记录升级集成结束时的状态；后续用户授权推送、原生验证与 DEB 测试包工作见 [Linux x64 DEB 记录](2026-09-14-linux-x64-deb.md)。

## 基线与范围

- 工作分支：`codex/linux-upstream-0897-port`。
- 集成前提交：`3a766a9015760285fc19015724dbfab36436acd1`。
- 参考：[FlClash v0.8.98](https://github.com/chen08209/FlClash/releases/tag/v0.8.98)，提交 `7c61c90ac20493b474d19c75ec96262b478b4b88`。
- 本次是 Linux 相关模块的选择性移植，不是整树替换或完整合并上游历史。当前仓库是浅克隆，不能从缺少 merge-base 推断历史无关。
- 按最新要求先完成升级集成；不推进新客户端功能、正式打包、远端推送或发布。后续首发目标仍为 Ubuntu / Debian x64 `.deb`。

## 集成内容

- 上游 Linux systemd Helper：polkit 安装、Unix socket、用户身份校验、固定 Core SHA256、会话级进程归属和退出清理；共享 Helper 客户端同时保留 Windows loopback 路径。
- Linux 托盘声明式更新：导入上游 Linux 后端，将现有业务菜单适配过去，保留 Windows/macOS 的旧托盘实现。
- Linux 重复启动唤醒：runner 接入上游窗口激活协议，固定匹配的 `window_manager` 版本，保留当前窗口尺寸。
- v0.8.98 IPC 写入修复：长时间挂起后继续写完已开始的帧，避免半帧破坏连接协议。
- v0.8.98 Geo 数据刷新修复：完成更新后重新读取文件大小/时间，并增加真实临时文件的 Widget 回归。
- 延用既有 buildkit：原生 Linux 构建输出 Core、release Helper 和 SHA manifest，CMake 一起安装；补齐现有 `.deb` 元数据、卸载清理、预检和 CI 验证约束，但未执行打包。

## 保留与取舍

- 保留现有登录、订阅、Xboard、工单、业务 UI、远程配置及其加密/签名链路。
- 保留既有桌面 latest-intent 生命周期与未确认退出时的进程归属保护；不会在旧 Core 仍可能运行时盲目启动替代进程。
- 不迁移上游整套 native-assets hooks，不调整 Android/macOS 构建架构，不更换锁定的 Clash.Meta 子模块版本，不改应用版本号。
- Helper 不用于 AppImage 或无 systemd 环境。上游服务只绑定一个 Linux 用户；多用户桌面切换需单独验收。
- 上游托盘新增能力不等于本产品已开放同名功能；本次以复用现有菜单和行为为准。

## 验证结果

验证主机为 macOS；以下通过项不代表 Linux 成品验收：

- 根包全量 `flutter test --no-pub --reporter expanded`：1798 项通过，1 项按原有开关跳过的真实网络诊断测试。
- 根包 Flutter 静态分析、build_runner 生成：通过。
- `plugins/tray`：静态分析通过，15 项测试通过。
- buildkit `build_tool`：静态分析通过，43 项测试通过。
- Helper：26 项主机共享协议测试通过；Linux x64 `cargo check --locked --tests --target x86_64-unknown-linux-gnu` 通过；Windows x64 对应检查并启用 `windows-service` 通过；Rust 格式检查通过。
- Go 包装层：应用仓库既有 mixed-listener-readiness 补丁后，`CGO_ENABLED=0 go test .` 和 `go vet .` 通过。
- `git diff --check`、Linux 预检脚本语法检查通过。

新增覆盖包括 polkit 成功/取消/缺失、安装后就绪握手、systemd/AppImage 条件、真实 Unix socket Helper 协议、Linux 菜单回调/禁用状态、平台构建参数和 Geo 文件更新。回归期间修正了上游日志工具函数不兼容，以及资源刷新 `setState` 回调误返回 Future 的集成问题。

## 后续验收边界

尚未在 Linux 执行原生链接、systemd/polkit/TUN、托盘桌面环境、重复启动/深链、网络切换和安装/升级/卸载测试；没有产出 `.deb`。Windows 跨目标检查也不替代真实 SCM/进程退出验收。

后续 Linux 客户端阶段应在 Ubuntu / Debian x64 原生环境完成这些验收，再提供测试安装包。当前 CI 只是补齐验证步骤，未触发远端流水线。

Core 测试通过仓库已有工具应用跟踪补丁，测试后已还原本次自动应用的子模块工作区改动，未产生新的子模块提交或修改 gitlink；后续构建仍由同一工具校验并应用。
