# 2026-09-03 API 登录容错与流量刷新

## 开发范围

- 改善非灰度账号登录时偶发“找不到 API”、需要重复点击的问题。
- 在桌面端和移动端加速主页的流量详情卡片增加纯图标刷新按钮。
- 本次仅完成客户端本地开发、静态检查和自动化测试，未打包、未部署。

## 登录容错设计

- 单次登录操作内按 `0 ms / 250 ms / 750 ms` 重试加载远程 API 配置。
- 登录不再依赖登录前的 HEAD 健康探测结果，改为对远程配置中的候选 API 发起真实登录请求并自动切换。
- 登录成功后记住本次可用 API；远程配置临时不可用时，使用上次成功 API 兜底。
- 有效远程配置明确返回空 API 列表时不使用历史地址，避免配置端主动下线失效。
- 保持 V2 安全边界：网络异常、API 异常和签名异常均不得降级 V1；仅服务端签名确认 `not_in_gray_allowlist` 时允许使用 V1。

## 流量刷新设计

- 桌面端和移动端均在流量详情标题右侧显示 `refresh_rounded` 图标。
- 刷新过程中显示圆形进度动画并禁止重复触发。
- 无网络、未登录或缺少刷新回调时按钮不可用。
- 刷新成功后通过订阅会话修订通知立即重绘剩余流量数据。
- 刷新失败时复用现有本地化错误提示。

## 主要修改文件

- `lib/common/api_health.dart`
- `lib/common/xboard_auth.dart`
- `lib/views/dashboard/dashboard.dart`
- `lib/views/dashboard/fengwo_desktop_dashboard.dart`
- `lib/views/dashboard/fengwo_mobile_dashboard.dart`
- `lib/views/dashboard/widgets/dashboard_subscription_refresh_button.dart`
- `test/common/api_health_test.dart`
- `test/common/xboard_auth_test.dart`
- `test/widgets/dashboard_layout_test.dart`

## 验证记录

- `flutter analyze --no-fatal-infos`：通过，0 个问题。
- API 健康、登录、V2 安全边界、仪表盘、流量详情及套餐购买相关测试：82 项全部通过。
- `git diff --check`：通过。

## 发布与回滚说明

- 本记录对应客户端代码提交，不包含服务端或数据库变更。
- 尚未生成安装包，也未部署到生产环境。
- 如需撤销，可对本次提交执行普通 `git revert <commit>`，无需处理数据库。
