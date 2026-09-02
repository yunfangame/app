# 2026-09-03 移动端退出功能

## 开发范围

- 在移动端个人中心底部增加退出账号按钮。
- 桌面端侧栏与移动端共用同一套退出确认和会话清理逻辑。
- 退出前显示确认对话框，取消操作不会改变当前登录状态。
- 确认退出后调用应用现有的账号退出流程，由该流程负责停止连接、清理会话并返回登录页。

## 主要修改文件

- `lib/widgets/fengwo_logout_button.dart`
- `lib/views/account/fengwo_personal_center.dart`
- `lib/manager/app_manager.dart`
- `test/widgets/personal_center_test.dart`

## 验证记录

- 个人中心相关界面测试：2 项全部通过。
- `flutter analyze --no-fatal-infos`：通过，0 个问题。
- 本次提交不包含客户端版本号修改、远程配置文件或服务端变更。

## 回滚说明

- 本功能为纯客户端改动，不涉及数据库。
- 如需撤销，可执行 `git revert <commit>`。
