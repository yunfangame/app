# 蜂窝加速器 Linux x64 测试包

本阶段基于 `codex/linux-upstream-0897-port`，复用现有登录、订阅、节点、工单与桌面功能。
验收目标为 Ubuntu 22.04 / Debian 12 x64 桌面环境；不承诺尚未验证的其他版本、ARM、RPM 或 AppImage。

## 安装

将 `.deb` 和 `SHA256SUMS` 放在同一目录，执行：

```bash
sha256sum -c SHA256SUMS
sudo apt install ./FlClash-*-linux-amd64.deb
```

以实际下载文件名为准。随后从应用菜单打开“蜂窝加速器”，不要使用 `sudo` 启动图形客户端。
覆盖安装前请从托盘退出旧版本。已有的配置和账号数据沿用原有目录。

首次启用 TUN 时，通过系统授权弹窗安装 Helper。Helper 依赖 systemd/polkit，并只绑定安装时的用户。
其他用户不能接管已有 Helper；无权限或取消授权时，不能据此认为 TUN 已生效。

GNOME 桌面需要支持 AppIndicator 的托盘扩展才能显示托盘图标。缺少托盘时仍可从应用菜单重新打开窗口。
Linux 的系统代理作用范围取决于桌面和应用，部分程序不会读取桌面代理设置；TUN 需单独验证。
未运行 NetworkManager 时，客户端会降级为定时检测网卡状态，不会强制安装或启动 NetworkManager。

## 检查与卸载

可运行 `bash ./fengwo-linux-preflight.sh --check-only` 收集依赖和环境检查结果。该模式不安装依赖或修改代理。
自动修复模式会安装依赖并可能重置失效的桌面代理，仅在了解其影响后使用。

退出客户端后可用安装包中的包名卸载：

```bash
dpkg-deb -f ./FlClash-*-linux-amd64.deb Package
sudo apt remove flclash
```

以第一条命令显示的实际包名为准。卸载会清理 Helper 服务，但不会主动删除用户配置。

## 验证边界

CI 检查应用回归、原生构建、安装/重装/卸载、Helper 哈希及会话隔离、IPC、服务退出回收、虚拟显示器下的启动和重复启动。
Debian 容器只验证依赖、图形启动和卸载，不代表验证了真实 systemd 或桌面授权弹窗。

发布前仍需在真实桌面检查登录与订阅、节点连接、系统代理、TUN、授权取消、托盘操作、休眠恢复和网络切换。
测试包不是正式 Release，不能将“构建成功”视为全部业务和网络场景已验收。
