// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a zh_CN locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(current, total) => "${current} / ${total}";

  static String m1(index) => "API 节点 ${index}";

  static String m2(reachable, total) => "${reachable}/${total} 个 API 接口可用";

  static String m3(status) => "API 返回 HTTP ${status}，请稍后重试或导出日志交给客服。";

  static String m4(status) => "服务器或中间代理拒绝访问（HTTP ${status}），不能据此认定邮箱或密码错误。";

  static String m5(version) => "发现新版本 ${version}";

  static String m6(version) => "当前版本 ${version}";

  static String m7(version) => "${version} 已是最新版本";

  static String m8(received, total) => "${received} / ${total}";

  static String m9(current, latest) => "当前 ${current}  →  最新 ${latest}";

  static String m10(index) => "穿透${index}线路";

  static String m11(count) => "共计 ${count} 个国家和地区";

  static String m12(count) => "${count} 天前";

  static String m13(label) => "确定删除选中的${label}吗？";

  static String m14(label) => "确定删除当前${label}吗？";

  static String m15(port) => "当前端口：${port}";

  static String m16(code) => "错误代码：${code}";

  static String m17(label) => "${label}详情";

  static String m18(entry) =>
      "过滤项格式有误：${entry}。请填写域名、完整标签通配符、geosite:名称 或 rule-set:名称，不要填网址或空格。";

  static String m19(count) => "已保存 ${count} 项";

  static String m20(label) => "${label}不能为空";

  static String m21(count) => "${count} 个条目";

  static String m22(label) => "${label}当前已存在";

  static String m23(date) => "首次登录：${date}";

  static String m24(name) => "${name} 已是最新版本";

  static String m25(name) => "${name} 已更新";

  static String m26(name) => "正在更新 ${name}...";

  static String m27(count) => "${count} 小时前";

  static String m28(count) => "${count} 小时";

  static String m29(target) => "${target} 是一个无效的策略";

  static String m30(proxyName) => "${proxyName} 是一个无效的代理";

  static String m31(providerName) => "${providerName} 是一个无效的代理集";

  static String m32(subRule) => "${subRule} 是一个无效的SUB_RULE";

  static String m33(date) => "最近登录：${date}";

  static String m34(port, code) =>
      "本地代理启动失败（${code}，端口 ${port}），已断开连接。请导出日志排查。";

  static String m35(count) => "${count} 个连接";

  static String m36(appName) =>
      "1. 打开 系统设置 > 隐私与安全性\n2. 选择 定位服务\n3. 在右侧列表中找到并勾选 ${appName}\n\n完成设置后，返回应用即可正常使用。感谢您的配合。";

  static String m37(index) => "站点${index}";

  static String m38(reason) => "原因：${reason}";

  static String m39(count) => "登录 ${count} 次";

  static String m40(count) => "${count} 分钟前";

  static String m41(count) => "${count} 个月前";

  static String m42(reachable, total) => "${reachable}/${total} 可解析";

  static String m43(address) => "${address} 正在监听";

  static String m44(address) => "${address} 无法连接";

  static String m45(code, stage, error) => "${code} / ${stage}${error}";

  static String m46(address) => "已回读并确认 ${address}";

  static String m47(status) => "访问未通过 · HTTP ${status}";

  static String m48(milliseconds, status) =>
      "可访问 · HTTPS 延迟 ${milliseconds} ms · HTTP ${status}";

  static String m49(date) => "下次套餐重置时间：${date}";

  static String m50(count) => "共计 ${count} 个节点";

  static String m51(label) => "暂无${label}";

  static String m52(label) => "${label}必须为数字";

  static String m53(current, total) => "第 ${current} / ${total} 页";

  static String m54(count) => "${count}人";

  static String m55(label) => "${label} 必须在 1024 到 49151 之间";

  static String m56(value) => "${value} ms";

  static String m57(count) => "已保存 ${count} 个，开启覆写后生效";

  static String m58(profile) => "当前订阅：${profile}";

  static String m59(count) => "${count} 秒";

  static String m60(count) => "已选择 ${count} 项";

  static String m61(date) => "套餐已于 ${date} 到期，请及时续费后继续使用。";

  static String m62(date) => "套餐将在 ${date} 到期，剩余不足 7 天，请及时续费。";

  static String m63(remaining) => "剩余流量仅 ${remaining} GB，已不足 10 GB，请及时购买或续费套餐。";

  static String m64(days, date) => "距离下次流量重置还有 ${days} 天（${date}）";

  static String m65(date) => "距离下次流量重置不足 1 天（${date}）";

  static String m66(code) => "系统代理开启失败（${code}），开关已回滚，请导出日志排查";

  static String m67(code) => "系统代理关闭失败（${code}），请在 Windows 设置中手动关闭";

  static String m68(count) => "共 ${count} 个订单";

  static String m69(port) =>
      "内部辅助服务端口 ${port} 被其他程序占用。请退出冲突程序及其辅助服务后重试，或导出日志联系客服。修改代理端口或重复授权无法释放此端口。";

  static String m70(ip) => "解除后，IP ${ip} 可以再次登录此账号。";

  static String m71(label) => "${label}必须为URL";

  static String m72(count) => "${count} 年前";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("关于"),
    "acceleratorHome": MessageLookupByLibrary.simpleMessage("加速主页"),
    "accessControl": MessageLookupByLibrary.simpleMessage("访问控制"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "只允许选中应用进入VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage("配置应用访问代理"),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "选中应用将会被排除在VPN之外",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage("访问控制设置"),
    "accessTime": MessageLookupByLibrary.simpleMessage("访问时间"),
    "account": MessageLookupByLibrary.simpleMessage("账号"),
    "accountBalance": MessageLookupByLibrary.simpleMessage("账户余额"),
    "accountCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "管理你的账户信息与安全设置",
    ),
    "action": MessageLookupByLibrary.simpleMessage("操作"),
    "action_mode": MessageLookupByLibrary.simpleMessage("切换模式"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "action_start": MessageLookupByLibrary.simpleMessage("启动/停止"),
    "action_tun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "action_view": MessageLookupByLibrary.simpleMessage("显示/隐藏"),
    "actions": MessageLookupByLibrary.simpleMessage("操作"),
    "activateNow": MessageLookupByLibrary.simpleMessage("立即开通"),
    "actualConnectionDelay": MessageLookupByLibrary.simpleMessage("实际延迟"),
    "add": MessageLookupByLibrary.simpleMessage("添加"),
    "addProfile": MessageLookupByLibrary.simpleMessage("添加配置"),
    "addProxies": MessageLookupByLibrary.simpleMessage("添加代理"),
    "addProxy": MessageLookupByLibrary.simpleMessage("添加代理"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("添加策略组"),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage("添加代理集"),
    "addRule": MessageLookupByLibrary.simpleMessage("添加规则"),
    "addSsid": MessageLookupByLibrary.simpleMessage("添加SSID"),
    "addedRules": MessageLookupByLibrary.simpleMessage("附加规则"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage("附加参数"),
    "address": MessageLookupByLibrary.simpleMessage("地址"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAV服务器地址"),
    "addressTip": MessageLookupByLibrary.simpleMessage("请输入有效的WebDAV地址"),
    "advancedConfig": MessageLookupByLibrary.simpleMessage("进阶配置"),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage("提供多样化配置"),
    "advancedSettings": MessageLookupByLibrary.simpleMessage("高级设置"),
    "advancedSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "自定义 VPN 行为与网络参数，打造专属连接体验",
    ),
    "allGeodataUpdated": MessageLookupByLibrary.simpleMessage("全部地理数据已更新"),
    "allPlans": MessageLookupByLibrary.simpleMessage("全部"),
    "allRemainingTraffic": MessageLookupByLibrary.simpleMessage("其余所有流量"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("允许应用绕过VPN"),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage("开启后部分应用可绕过VPN"),
    "allowLan": MessageLookupByLibrary.simpleMessage("局域网代理"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage("允许通过局域网访问代理"),
    "alreadyHaveAccount": MessageLookupByLibrary.simpleMessage("已有账号？"),
    "announcementCenter": MessageLookupByLibrary.simpleMessage("公告中心"),
    "announcementPosition": m0,
    "announcementTooltip": MessageLookupByLibrary.simpleMessage("查看公告"),
    "announcementUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "离线模式下无法获取最新公告",
    ),
    "apiDiagnostics": MessageLookupByLibrary.simpleMessage("API 诊断"),
    "apiEndpointLabel": m1,
    "apiEndpointsAvailable": m2,
    "apiFailureCancelled": MessageLookupByLibrary.simpleMessage(
      "API 请求已取消，可以重试。",
    ),
    "apiFailureConfiguration": MessageLookupByLibrary.simpleMessage(
      "API 配置缺失或无效，请刷新配置或联系客服。",
    ),
    "apiFailureDecrypt": MessageLookupByLibrary.simpleMessage(
      "远程配置解密失败，请刷新配置或联系客服。",
    ),
    "apiFailureDns": MessageLookupByLibrary.simpleMessage(
      "API 域名解析失败，请检查网络和 DNS 设置。",
    ),
    "apiFailureHelp": MessageLookupByLibrary.simpleMessage(
      "可重试、检查联网权限，或导出日志交给客服。仅凭此错误无法确认是防火墙或杀毒软件拦截，请勿直接关闭防护。",
    ),
    "apiFailureHttp": m3,
    "apiFailureHttpDenied": m4,
    "apiFailureNetwork": MessageLookupByLibrary.simpleMessage(
      "API 连接失败，请运行 API 诊断并导出日志分析。",
    ),
    "apiFailureNoEndpoints": MessageLookupByLibrary.simpleMessage(
      "配置中没有可用的 API 地址，请刷新配置或联系客服。",
    ),
    "apiFailurePermission": MessageLookupByLibrary.simpleMessage(
      "联网权限被拒绝，可能涉及系统或安全策略，尚不能确定是哪个软件导致。",
    ),
    "apiFailureRateLimited": MessageLookupByLibrary.simpleMessage(
      "API 请求过于频繁（HTTP 429），请稍后重试。",
    ),
    "apiFailureRefused": MessageLookupByLibrary.simpleMessage(
      "API 连接被拒绝，可能是目标服务未开放或网络策略拒绝。",
    ),
    "apiFailureReset": MessageLookupByLibrary.simpleMessage(
      "API 连接被中断或重置，请重试，或换一个网络对比。",
    ),
    "apiFailureSignature": MessageLookupByLibrary.simpleMessage(
      "远程配置校验失败，未使用不可信配置，请联系客服。",
    ),
    "apiFailureTimeout": MessageLookupByLibrary.simpleMessage(
      "API 请求超时，可能是网络或服务暂不可用，尚不能确认存在拦截。",
    ),
    "apiFailureTls": MessageLookupByLibrary.simpleMessage(
      "安全连接校验失败，请检查系统时间、证书和网络设置；请勿跳过证书校验。",
    ),
    "apiLogExportFailed": MessageLookupByLibrary.simpleMessage("日志导出失败，请重试。"),
    "apiReachabilityHint": MessageLookupByLibrary.simpleMessage(
      "客户端登录时会从多个 API 中自动选择可用站点；这里只检测配置与 API 连通性，不代表登录一定成功，也不支持手动指定。",
    ),
    "apiStatus": MessageLookupByLibrary.simpleMessage("API 连通状态"),
    "apiStatusUnavailable": MessageLookupByLibrary.simpleMessage(
      "暂时无法获取 API 连通状态",
    ),
    "app": MessageLookupByLibrary.simpleMessage("应用"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("应用访问控制"),
    "appRouting": MessageLookupByLibrary.simpleMessage("应用分流"),
    "appRoutingAllApps": MessageLookupByLibrary.simpleMessage("全部应用"),
    "appRoutingApps": MessageLookupByLibrary.simpleMessage("应用列表"),
    "appRoutingAppsHint": MessageLookupByLibrary.simpleMessage(
      "默认展示可从桌面打开的联网应用",
    ),
    "appRoutingConnectionHint": MessageLookupByLibrary.simpleMessage(
      "修改后需重新连接 VPN，期间网络会短暂中断。",
    ),
    "appRoutingDescription": MessageLookupByLibrary.simpleMessage(
      "选择哪些应用直接联网，不经过 VPN",
    ),
    "appRoutingDirectMode": MessageLookupByLibrary.simpleMessage("所选应用直连"),
    "appRoutingEmptyHint": MessageLookupByLibrary.simpleMessage(
      "没有匹配的应用，可调整搜索或切换“全部应用”",
    ),
    "appRoutingLoadFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取应用列表，请重试",
    ),
    "appRoutingPolicy": MessageLookupByLibrary.simpleMessage("分流设置"),
    "appRoutingProxyMode": MessageLookupByLibrary.simpleMessage("仅所选应用使用 VPN"),
    "appRoutingReconnect": MessageLookupByLibrary.simpleMessage("保存并重新连接"),
    "appRoutingReconnecting": MessageLookupByLibrary.simpleMessage(
      "已保存，正在重新连接",
    ),
    "appRoutingSaveFailed": MessageLookupByLibrary.simpleMessage(
      "保存或重新连接失败，请重试",
    ),
    "appRoutingSaved": MessageLookupByLibrary.simpleMessage("应用分流设置已保存"),
    "appRoutingSearchHint": MessageLookupByLibrary.simpleMessage("搜索应用名称或包名"),
    "appUpdateAvailable": m5,
    "appUpdateBackground": MessageLookupByLibrary.simpleMessage("后台下载"),
    "appUpdateCancelDownload": MessageLookupByLibrary.simpleMessage("取消下载"),
    "appUpdateChecking": MessageLookupByLibrary.simpleMessage("正在检查更新…"),
    "appUpdateChecksumMismatch": MessageLookupByLibrary.simpleMessage(
      "下载文件校验失败，请重新下载。",
    ),
    "appUpdateChecksumMissing": MessageLookupByLibrary.simpleMessage(
      "更新缺少文件校验信息，暂时无法下载，请联系客服。",
    ),
    "appUpdateCurrentVersion": m6,
    "appUpdateDownload": MessageLookupByLibrary.simpleMessage("下载更新"),
    "appUpdateDownloadCancelled": MessageLookupByLibrary.simpleMessage("下载已取消"),
    "appUpdateDownloadDetails": MessageLookupByLibrary.simpleMessage("下载详情"),
    "appUpdateDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "下载失败，请检查网络后重试。",
    ),
    "appUpdateDownloadReady": MessageLookupByLibrary.simpleMessage(
      "下载和校验已完成，可以安装更新。",
    ),
    "appUpdateDownloading": MessageLookupByLibrary.simpleMessage("正在下载更新…"),
    "appUpdateFailed": MessageLookupByLibrary.simpleMessage("检查更新失败，请稍后重试。"),
    "appUpdateIgnoreVersion": MessageLookupByLibrary.simpleMessage("不再提示此版本"),
    "appUpdateInstall": MessageLookupByLibrary.simpleMessage("安装更新"),
    "appUpdateInstallerOpenFailed": MessageLookupByLibrary.simpleMessage(
      "无法打开安装程序，请重试。",
    ),
    "appUpdateInstallerOpened": MessageLookupByLibrary.simpleMessage(
      "安装程序已打开，请按提示完成更新。",
    ),
    "appUpdateInstalling": MessageLookupByLibrary.simpleMessage("正在打开安装程序…"),
    "appUpdateLater": MessageLookupByLibrary.simpleMessage("稍后提醒"),
    "appUpdateLatest": m7,
    "appUpdateOpenFailed": MessageLookupByLibrary.simpleMessage(
      "无法打开下载链接，请稍后重试。",
    ),
    "appUpdateProgress": m8,
    "appUpdateRetry": MessageLookupByLibrary.simpleMessage("重试"),
    "appUpdateUnavailable": MessageLookupByLibrary.simpleMessage(
      "暂时无法获取当前平台的更新信息，请稍后重试。",
    ),
    "appUpdateUnsupportedPackage": MessageLookupByLibrary.simpleMessage(
      "暂不支持在软件内安装此更新包。",
    ),
    "appUpdateVerifying": MessageLookupByLibrary.simpleMessage("正在校验下载文件…"),
    "appUpdateVersionSummary": m9,
    "appendSystemDns": MessageLookupByLibrary.simpleMessage("追加系统DNS"),
    "appendSystemDnsTip": MessageLookupByLibrary.simpleMessage("强制为配置附加系统DNS"),
    "application": MessageLookupByLibrary.simpleMessage("应用程序"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage("修改应用程序相关设置"),
    "applyPreferredIps": MessageLookupByLibrary.simpleMessage("全部替换"),
    "asnLabel": MessageLookupByLibrary.simpleMessage("ASN"),
    "authorized": MessageLookupByLibrary.simpleMessage("已授权"),
    "auto": MessageLookupByLibrary.simpleMessage("自动"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage("自动检查更新"),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage("应用启动时自动检查更新"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("自动关闭连接"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "手动切换节点后自动关闭已有连接",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("开机自启"),
    "autoLaunchApplying": MessageLookupByLibrary.simpleMessage("正在应用启动设置…"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "登录系统后自动启动蜂窝加速器，默认关闭。",
    ),
    "autoLaunchFailed": MessageLookupByLibrary.simpleMessage(
      "无法更改开机自启设置，请检查系统权限后重试。",
    ),
    "autoLaunchPersistenceFailed": MessageLookupByLibrary.simpleMessage(
      "无法保存开机自启设置，已恢复之前的状态，请重试。",
    ),
    "autoLaunchReadFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取系统启动设置，请重试后再更改。",
    ),
    "autoLaunchReading": MessageLookupByLibrary.simpleMessage("正在读取系统启动设置…"),
    "autoLaunchRollbackFailed": MessageLookupByLibrary.simpleMessage(
      "无法恢复之前的设置，请在系统设置中检查启动应用。",
    ),
    "autoLaunchVerificationFailed": MessageLookupByLibrary.simpleMessage(
      "系统未确认设置生效，开机自启设置未更改，请重试。",
    ),
    "autoRefresh": MessageLookupByLibrary.simpleMessage("自动刷新"),
    "autoRenew": MessageLookupByLibrary.simpleMessage("自动续费"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自动运行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("应用打开时自动运行"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("自动设置系统DNS"),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自动更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔（分钟）"),
    "automaticLogin": MessageLookupByLibrary.simpleMessage("自动登录"),
    "automaticLoginUnavailable": MessageLookupByLibrary.simpleMessage(
      "自动登录暂时失败，请手动登录或稍后重试",
    ),
    "automaticSelection": MessageLookupByLibrary.simpleMessage("自动选择"),
    "availabilityRate": MessageLookupByLibrary.simpleMessage("可用率"),
    "availableCommissionEmpty": MessageLookupByLibrary.simpleMessage("暂无可划转佣金"),
    "availableCount": MessageLookupByLibrary.simpleMessage("可用"),
    "availableEndpoints": MessageLookupByLibrary.simpleMessage("可用站点"),
    "backToLogin": MessageLookupByLibrary.simpleMessage("返回登录"),
    "backup": MessageLookupByLibrary.simpleMessage("备份"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage("备份与恢复"),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "通过WebDAV或者文件同步数据",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("备份成功"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("基本配置"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage("全局修改基本配置"),
    "basicInfo": MessageLookupByLibrary.simpleMessage("基础信息"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("基础策略"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "为保证后台运行，请关闭本应用的电池优化。点击前往设置。",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "受系统影响，不代表一定准确",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("绑定"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("黑名单模式"),
    "blockLoginIp": MessageLookupByLibrary.simpleMessage("拉黑"),
    "blockLoginIpTitle": MessageLookupByLibrary.simpleMessage("拉黑这个登录 IP？"),
    "blockLoginIpWarning": MessageLookupByLibrary.simpleMessage(
      "拉黑后，该 IP 将无法再次登录此账号；当前已登录会话不会被强制退出。共享网络下也可能影响你自己的其他设备。",
    ),
    "blockReasonHint": MessageLookupByLibrary.simpleMessage("例如：不是我本人登录"),
    "blockReasonOptional": MessageLookupByLibrary.simpleMessage("原因（选填）"),
    "blockedIpCount": MessageLookupByLibrary.simpleMessage("已拉黑"),
    "bound": MessageLookupByLibrary.simpleMessage("已绑定"),
    "brandName": MessageLookupByLibrary.simpleMessage("蜂窝加速器"),
    "buyNow": MessageLookupByLibrary.simpleMessage("立即购买"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("排除域名"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage("仅在系统代理启用时生效"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage("缓存已损坏，是否清空？"),
    "campusNetworkApplyFailed": MessageLookupByLibrary.simpleMessage(
      "校园网模式应用失败，请检查网络后重试",
    ),
    "campusNetworkDisabled": MessageLookupByLibrary.simpleMessage(
      "校园网模式已关闭并生效",
    ),
    "campusNetworkEnabled": MessageLookupByLibrary.simpleMessage("校园网模式已开启并生效"),
    "campusNetworkInformation": MessageLookupByLibrary.simpleMessage(
      "关闭时继续使用 CDN 正常解析；开启或切换线路后会自动重新加载内核配置。",
    ),
    "campusNetworkLine": MessageLookupByLibrary.simpleMessage("穿透线路"),
    "campusNetworkLine1": MessageLookupByLibrary.simpleMessage("穿透1线路"),
    "campusNetworkLine2": MessageLookupByLibrary.simpleMessage("穿透2线路"),
    "campusNetworkLine3": MessageLookupByLibrary.simpleMessage("穿透3线路"),
    "campusNetworkLineNumber": m10,
    "campusNetworkMode": MessageLookupByLibrary.simpleMessage("校园网模式"),
    "campusNetworkModeSubtitle": MessageLookupByLibrary.simpleMessage(
      "为校园网络切换专用入口线路",
    ),
    "campusNetworkSwitch": MessageLookupByLibrary.simpleMessage("启用校园网模式"),
    "campusNetworkSwitchDescription": MessageLookupByLibrary.simpleMessage(
      "开启后将节点域名映射到所选线路的入口 IP",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("取消"),
    "cancelOrder": MessageLookupByLibrary.simpleMessage("取消订单"),
    "cancelOrderMessage": MessageLookupByLibrary.simpleMessage(
      "订单取消后无法继续支付，需要时可重新下单。",
    ),
    "cancelOrderTitle": MessageLookupByLibrary.simpleMessage("取消这个订单？"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("取消全选"),
    "candidateCount": MessageLookupByLibrary.simpleMessage("候选"),
    "carrier": MessageLookupByLibrary.simpleMessage("运营商"),
    "cfApplyFailed": MessageLookupByLibrary.simpleMessage(
      "CF 优选 IP 应用失败，已恢复原配置",
    ),
    "cfApplySuccess": MessageLookupByLibrary.simpleMessage(
      "CF 优选 IP 已应用，内核配置已重新加载",
    ),
    "cfTargetMissingMessage": MessageLookupByLibrary.simpleMessage(
      "请先在远程配置文件中填写 CF 优选要替换的节点域名。",
    ),
    "cfTargetMissingTitle": MessageLookupByLibrary.simpleMessage("未配置目标域名"),
    "cfTargetValidationFailed": MessageLookupByLibrary.simpleMessage(
      "优选 IP 无法通过目标域名的 TLS 校验，未修改配置",
    ),
    "chainProxy": MessageLookupByLibrary.simpleMessage("链式代理管理"),
    "chainProxyActive": MessageLookupByLibrary.simpleMessage("当前链式代理已启动"),
    "chainProxyApplyFailed": MessageLookupByLibrary.simpleMessage(
      "内核应用失败，已恢复原配置",
    ),
    "chainProxyConnectivityFailed": MessageLookupByLibrary.simpleMessage(
      "链式代理联网检测失败，已自动停用并恢复原配置",
    ),
    "chainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "管理链式出口，让订阅节点连接后通过它出站",
    ),
    "chainProxyDirectModeUnsupported": MessageLookupByLibrary.simpleMessage(
      "请先将出站模式切换为规则或全局模式",
    ),
    "chainProxyDisabled": MessageLookupByLibrary.simpleMessage("当前未启用链式代理"),
    "chainProxyEnabled": MessageLookupByLibrary.simpleMessage("链式代理已启动"),
    "chainProxyLocked": MessageLookupByLibrary.simpleMessage(
      "链式代理运行期间，其他配置暂不可操作",
    ),
    "chainProxyRollbackFailed": MessageLookupByLibrary.simpleMessage(
      "链式代理应用失败且无法恢复原配置，请重启客户端",
    ),
    "chainProxySessionNotice": MessageLookupByLibrary.simpleMessage(
      "启用后，代理流量会先经过当前订阅节点，再通过链式代理出站。同一时间只能启用一个。",
    ),
    "chainProxyStopped": MessageLookupByLibrary.simpleMessage("链式代理已停止"),
    "changePasswordTitle": MessageLookupByLibrary.simpleMessage("修改密码"),
    "changePlanAction": MessageLookupByLibrary.simpleMessage("变更套餐"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("检查更新"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("当前应用已经是最新版了"),
    "checkingApiStatus": MessageLookupByLibrary.simpleMessage(
      "正在检测 API 连通性...",
    ),
    "checkingLoginStatus": MessageLookupByLibrary.simpleMessage("正在检查登录状态..."),
    "chooseSpeedTest": MessageLookupByLibrary.simpleMessage("选择测速"),
    "clearData": MessageLookupByLibrary.simpleMessage("清除数据"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("导出剪贴板"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("剪贴板导入"),
    "closeAction": MessageLookupByLibrary.simpleMessage("关闭"),
    "closeAllConnections": MessageLookupByLibrary.simpleMessage("关闭全部连接"),
    "closeAllConnectionsDescription": MessageLookupByLibrary.simpleMessage(
      "当前连接将全部断开，应用可能会自动重新连接。",
    ),
    "closeConnection": MessageLookupByLibrary.simpleMessage("断开连接"),
    "cloudflarePreferredIp": MessageLookupByLibrary.simpleMessage("CF 优选 IP"),
    "cloudflarePreferredIpDescription": MessageLookupByLibrary.simpleMessage(
      "自动寻找当前网络更快的 Cloudflare 入口",
    ),
    "color": MessageLookupByLibrary.simpleMessage("颜色"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("配色方案"),
    "columns": MessageLookupByLibrary.simpleMessage("列数"),
    "commission": MessageLookupByLibrary.simpleMessage("佣金"),
    "commissionPayoutRecords": MessageLookupByLibrary.simpleMessage("佣金发放记录"),
    "commissionRate": MessageLookupByLibrary.simpleMessage("佣金比例"),
    "commissionTransfer": MessageLookupByLibrary.simpleMessage("划转"),
    "commissionTransferConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "可用佣金将转入账户余额，转入后可用于购买套餐。",
    ),
    "commissionTransferConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "划转全部可用佣金？",
    ),
    "commissionTransferred": MessageLookupByLibrary.simpleMessage("佣金已划转到账户余额"),
    "commissionWithdraw": MessageLookupByLibrary.simpleMessage("佣金提现"),
    "compatible": MessageLookupByLibrary.simpleMessage("兼容模式"),
    "completedCount": MessageLookupByLibrary.simpleMessage("已完成"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage("检测到配置中存在数据"),
    "confirm": MessageLookupByLibrary.simpleMessage("确定"),
    "confirmBlockLoginIp": MessageLookupByLibrary.simpleMessage("确认拉黑"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage("确定要清除所有数据？"),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "确定要删除当前策略组吗？",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage("确定要退出当前窗口吗?"),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage("确定要强制崩溃核心？"),
    "confirmNewPassword": MessageLookupByLibrary.simpleMessage("确认新密码"),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage("确定后将会覆盖已有数据"),
    "confirmPassword": MessageLookupByLibrary.simpleMessage("确认密码"),
    "confirmReset": MessageLookupByLibrary.simpleMessage("确认重置"),
    "confirmUnblockLoginIp": MessageLookupByLibrary.simpleMessage("确认解除"),
    "connected": MessageLookupByLibrary.simpleMessage("已连接"),
    "connecting": MessageLookupByLibrary.simpleMessage("连接中..."),
    "connection": MessageLookupByLibrary.simpleMessage("连接"),
    "connectionDetails": MessageLookupByLibrary.simpleMessage("连接详情"),
    "connectionRuleAlreadyExists": MessageLookupByLibrary.simpleMessage(
      "该规则已存在，配置已重新应用",
    ),
    "connectionRuleApplied": MessageLookupByLibrary.simpleMessage("规则已添加并生效"),
    "connectionRuleAppliedAndSwitched": MessageLookupByLibrary.simpleMessage(
      "规则已添加，并已切换到规则模式",
    ),
    "connectionStatus": MessageLookupByLibrary.simpleMessage("连接状态"),
    "connections": MessageLookupByLibrary.simpleMessage("连接"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage("查看当前连接数据"),
    "connectivity": MessageLookupByLibrary.simpleMessage("连通性："),
    "consumptionOnly": MessageLookupByLibrary.simpleMessage("仅消费"),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage("内容不能为空"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("内容主题"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage("控制全局附加规则"),
    "copy": MessageLookupByLibrary.simpleMessage("复制"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("复制环境变量"),
    "copyInviteLink": MessageLookupByLibrary.simpleMessage("复制邀请链接"),
    "copyLink": MessageLookupByLibrary.simpleMessage("复制链接"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("复制成功"),
    "core": MessageLookupByLibrary.simpleMessage("内核"),
    "coreIpv6": MessageLookupByLibrary.simpleMessage("核心 IPv6"),
    "coreIpv6Description": MessageLookupByLibrary.simpleMessage(
      "控制 Mihomo 顶层 IPv6 能力",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("核心状态"),
    "countriesAndRegions": MessageLookupByLibrary.simpleMessage("国家与地区"),
    "countriesCount": m11,
    "country": MessageLookupByLibrary.simpleMessage("区域"),
    "countryRegion": MessageLookupByLibrary.simpleMessage("国家/地区"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("检测到崩溃"),
    "crashDetectedTip": MessageLookupByLibrary.simpleMessage(
      "检测到应用上次运行发生崩溃。为避免重复崩溃，已清除当前配置选择，并跳过本次自动配置。",
    ),
    "crashTest": MessageLookupByLibrary.simpleMessage("崩溃测试"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("崩溃分析"),
    "crashlyticsTip": MessageLookupByLibrary.simpleMessage(
      "开启后，应用崩溃时自动上传不包含敏感信息的崩溃日志",
    ),
    "create": MessageLookupByLibrary.simpleMessage("创建"),
    "createAccountSubtitle": MessageLookupByLibrary.simpleMessage(
      "加入我们,开始您的网络管理之旅",
    ),
    "createAccountTitle": MessageLookupByLibrary.simpleMessage("创建账号"),
    "createProfile": MessageLookupByLibrary.simpleMessage("创建配置"),
    "createdAt": MessageLookupByLibrary.simpleMessage("创建时间"),
    "creatingOrder": MessageLookupByLibrary.simpleMessage("正在创建订单…"),
    "creationTime": MessageLookupByLibrary.simpleMessage("创建时间"),
    "currentActiveConnections": MessageLookupByLibrary.simpleMessage("当前活跃连接"),
    "currentConnections": MessageLookupByLibrary.simpleMessage("当前连接"),
    "currentEndpoint": MessageLookupByLibrary.simpleMessage("选择方式"),
    "currentMonthTraffic": MessageLookupByLibrary.simpleMessage("本月流量"),
    "currentNode": MessageLookupByLibrary.simpleMessage("当前节点"),
    "currentNodeDelay": MessageLookupByLibrary.simpleMessage("当前节点延迟"),
    "currentPlanLabel": MessageLookupByLibrary.simpleMessage("当前套餐"),
    "custom": MessageLookupByLibrary.simpleMessage("自定义"),
    "customDnsServers": MessageLookupByLibrary.simpleMessage("自定义 DNS 服务器"),
    "cut": MessageLookupByLibrary.simpleMessage("剪切"),
    "dailyBrowsingRuleMode": MessageLookupByLibrary.simpleMessage(
      "日常访问：规则模式更稳妥。",
    ),
    "dark": MessageLookupByLibrary.simpleMessage("深色"),
    "dashboard": MessageLookupByLibrary.simpleMessage("仪表盘"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage("检测到数据有更改，是否保存"),
    "dataCollectionContent": MessageLookupByLibrary.simpleMessage(
      "本应用使用 Firebase Crashlytics 收集崩溃信息以改进应用稳定性。\n收集的数据包括设备信息和崩溃详情，不包含个人敏感数据。\n您可以在设置中关闭此功能。",
    ),
    "dataCollectionTip": MessageLookupByLibrary.simpleMessage("数据收集说明"),
    "dataSource": MessageLookupByLibrary.simpleMessage("数据来源"),
    "dateLabel": MessageLookupByLibrary.simpleMessage("日期"),
    "daysAgo": m12,
    "defaultNameserver": MessageLookupByLibrary.simpleMessage("默认域名服务器"),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage("用于解析DNS服务器"),
    "defaultText": MessageLookupByLibrary.simpleMessage("默认"),
    "delay": MessageLookupByLibrary.simpleMessage("延迟"),
    "delayTest": MessageLookupByLibrary.simpleMessage("延迟测试"),
    "delete": MessageLookupByLibrary.simpleMessage("删除"),
    "deleteMultipTip": m13,
    "deleteTip": m14,
    "desc": MessageLookupByLibrary.simpleMessage(
      "基于ClashMeta的多平台代理客户端，简单易用，开源无广告。",
    ),
    "desktopProxyAddressInUse": MessageLookupByLibrary.simpleMessage(
      "当前监听端口已被其他程序占用。请关闭占用该端口的程序后重试，或更换端口。",
    ),
    "desktopProxyAddressNotAvailable": MessageLookupByLibrary.simpleMessage(
      "配置的监听地址在当前电脑上不可用。请检查网络连接和绑定地址后重试。",
    ),
    "desktopProxyChangePort": MessageLookupByLibrary.simpleMessage("更换端口"),
    "desktopProxyConfigurationFailed": MessageLookupByLibrary.simpleMessage(
      "代理配置未能成功应用。请检查当前订阅和配置，或导出日志确认具体原因。",
    ),
    "desktopProxyCurrentPort": m15,
    "desktopProxyFailureCode": m16,
    "desktopProxyFailureLogs": MessageLookupByLibrary.simpleMessage("查看/导出日志"),
    "desktopProxyFailureLogsHint": MessageLookupByLibrary.simpleMessage(
      "可查看或导出日志，将错误信息发给客服排查。",
    ),
    "desktopProxyFailureTitle": MessageLookupByLibrary.simpleMessage("代理启动失败"),
    "desktopProxyInvalidBindAddress": MessageLookupByLibrary.simpleMessage(
      "监听地址格式无效，请检查代理配置中的绑定地址后重试。",
    ),
    "desktopProxyListenerAccessDenied": MessageLookupByLibrary.simpleMessage(
      "系统拒绝使用当前监听端口，可能与端口保留或安全策略有关。请检查系统限制，或尝试其他端口。",
    ),
    "desktopProxyLocalPortUnavailable": MessageLookupByLibrary.simpleMessage(
      "客户端未能连接到本地代理端口，尚不能确认是端口占用。请重试或导出日志排查，也可以尝试更换端口。",
    ),
    "desktopProxyPortHint": MessageLookupByLibrary.simpleMessage(
      "请输入 1024–49151 之间的新端口，不能与其他本地监听端口重复。保存后将重新尝试连接。",
    ),
    "desktopProxyPortRange": MessageLookupByLibrary.simpleMessage(
      "请输入 1024–49151 之间的整数端口",
    ),
    "desktopProxyPortReserved": MessageLookupByLibrary.simpleMessage(
      "该端口已用于其他本地监听服务，请选择其他端口",
    ),
    "desktopProxyPortSaveRetry": MessageLookupByLibrary.simpleMessage("保存并重试"),
    "desktopProxyPortUnchanged": MessageLookupByLibrary.simpleMessage(
      "新端口不能与当前端口相同",
    ),
    "desktopProxySystemAccessDenied": MessageLookupByLibrary.simpleMessage(
      "系统拒绝修改代理设置。请检查当前用户权限或系统管理策略后重试。",
    ),
    "desktopProxySystemFailed": MessageLookupByLibrary.simpleMessage(
      "系统代理设置未能完成。请重试；若仍然失败，请导出日志排查。",
    ),
    "desktopProxySystemFailureTitle": MessageLookupByLibrary.simpleMessage(
      "系统代理设置失败",
    ),
    "desktopProxySystemReadbackFailed": MessageLookupByLibrary.simpleMessage(
      "系统代理设置校验失败，实际设置与客户端请求不一致或无法读取。请检查是否有其他软件正在修改代理设置。",
    ),
    "desktopProxySystemWriteFailed": MessageLookupByLibrary.simpleMessage(
      "系统代理设置写入失败。请检查系统限制，或导出日志进一步排查。",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("目标地址"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage("目标地理定位"),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage("目标IP ASN"),
    "details": m17,
    "detectionTip": MessageLookupByLibrary.simpleMessage("依赖第三方api，仅供参考"),
    "developerMode": MessageLookupByLibrary.simpleMessage("开发者模式"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage("开发者模式已启用。"),
    "direct": MessageLookupByLibrary.simpleMessage("直连"),
    "disableProxy": MessageLookupByLibrary.simpleMessage("停止"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("禁用UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("已停用"),
    "disconnected": MessageLookupByLibrary.simpleMessage("已断开"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage("发现新版本"),
    "dnsAdvancedCampusOverrideActive": MessageLookupByLibrary.simpleMessage(
      "校园网模式正在强制覆写 DNS。校园网 hosts 配置生效期间，覆写开关由校园网模式管理。",
    ),
    "dnsAdvancedDnsDisabled": MessageLookupByLibrary.simpleMessage(
      "本机配置中的 DNS 已关闭，启用后才能使用这些设置。",
    ),
    "dnsAdvancedEnableDns": MessageLookupByLibrary.simpleMessage("启用本机 DNS"),
    "dnsAdvancedFakeIpActive": MessageLookupByLibrary.simpleMessage(
      "本机 DNS 配置使用 Fake-IP，下方过滤列表与范围会用于此配置。",
    ),
    "dnsAdvancedFakeIpInactive": MessageLookupByLibrary.simpleMessage(
      "当前模式不是 Fake-IP。过滤列表与范围会保存，但在此模式下不生效；可在上方主动选择 fake-ip。",
    ),
    "dnsAdvancedFilterDescription": MessageLookupByLibrary.simpleMessage(
      "命中过滤的域名会解析为真实 IP，而不是 Fake-IP。这不等于直连（DIRECT）；连接走直连还是代理，仍由分流规则决定。",
    ),
    "dnsAdvancedFilterEditingHint": MessageLookupByLibrary.simpleMessage(
      "每行一个域名或通配符，例如 *.example.com。通过增删整行编辑列表；保存时去除空行和完全重复项，并保留已有的高级条目。",
    ),
    "dnsAdvancedFilterEmpty": MessageLookupByLibrary.simpleMessage("暂无自定义过滤项"),
    "dnsAdvancedFilterInvalid": m18,
    "dnsAdvancedLocalFiltersHint": MessageLookupByLibrary.simpleMessage(
      "应用还会保留 localhost、*.local、*.lan 等局域网过滤项。清空这里的列表不会移除这些内置项。",
    ),
    "dnsAdvancedLocalOverrideActive": MessageLookupByLibrary.simpleMessage(
      "DNS 覆写已开启，本机 DNS 配置优先于订阅中的 DNS 配置。",
    ),
    "dnsAdvancedLocalOverrideInactive": MessageLookupByLibrary.simpleMessage(
      "DNS 覆写已关闭，通常优先使用订阅中的 DNS 配置；这里的修改仍会保存在本机。开启覆写后可固定使用这些设置。",
    ),
    "dnsAdvancedLocalSettings": MessageLookupByLibrary.simpleMessage(
      "这里编辑的是本机 DNS 设置。覆写开关和模式选择立即保存；过滤列表与范围在点击“保存”后更新。",
    ),
    "dnsAdvancedOptions": MessageLookupByLibrary.simpleMessage("DNS 高级选项"),
    "dnsAdvancedOptionsDescription": MessageLookupByLibrary.simpleMessage(
      "编辑 Fake-IP 过滤，查看设置生效条件",
    ),
    "dnsAdvancedRangeDescription": MessageLookupByLibrary.simpleMessage(
      "这是 Fake-IP 使用的虚拟 IPv4 地址池，不是代理地址或服务器地址。默认 198.18.0.1/16，通常无需修改；需要避免地址冲突时再调整。",
    ),
    "dnsAdvancedRangeInvalid": MessageLookupByLibrary.simpleMessage(
      "请输入前缀为 0–29 的 IPv4 CIDR，例如 198.18.0.1/16；地址池过小会导致核心无法启动。",
    ),
    "dnsAdvancedSavedFiltersCount": m19,
    "dnsDesc": MessageLookupByLibrary.simpleMessage("更新DNS相关设置"),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS劫持"),
    "dnsIpv6": MessageLookupByLibrary.simpleMessage("DNS IPv6"),
    "dnsIpv6Description": MessageLookupByLibrary.simpleMessage(
      "允许 DNS 查询返回 IPv6 记录",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS模式"),
    "dnsOverrideInformation": MessageLookupByLibrary.simpleMessage(
      "启用后将使用应用内置 DNS 配置，而非订阅中的 DNS 设置",
    ),
    "dnsSettings": MessageLookupByLibrary.simpleMessage("DNS 设置"),
    "dnsSettingsSubtitle": MessageLookupByLibrary.simpleMessage("管理 DNS 解析配置"),
    "doNotRemindToday": MessageLookupByLibrary.simpleMessage("今日不再提示"),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage("是否要通过"),
    "domain": MessageLookupByLibrary.simpleMessage("域名"),
    "domainOrService": MessageLookupByLibrary.simpleMessage("域名 / 服务"),
    "done": MessageLookupByLibrary.simpleMessage("完成"),
    "dontShowAgain": MessageLookupByLibrary.simpleMessage("不再显示"),
    "download": MessageLookupByLibrary.simpleMessage("下载"),
    "downloadSpeed": MessageLookupByLibrary.simpleMessage("下载速度"),
    "downloadTraffic": MessageLookupByLibrary.simpleMessage("下载流量"),
    "downloaded": MessageLookupByLibrary.simpleMessage("已下载"),
    "edit": MessageLookupByLibrary.simpleMessage("编辑"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage("编辑全局规则"),
    "editProxy": MessageLookupByLibrary.simpleMessage("修改代理"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("编辑策略组"),
    "editRule": MessageLookupByLibrary.simpleMessage("编辑规则"),
    "editSsid": MessageLookupByLibrary.simpleMessage("编辑SSID"),
    "email": MessageLookupByLibrary.simpleMessage("邮箱"),
    "emailVerificationCode": MessageLookupByLibrary.simpleMessage("邮箱验证码"),
    "emptyTip": m20,
    "en": MessageLookupByLibrary.simpleMessage("英语"),
    "enableOfflineAction": MessageLookupByLibrary.simpleMessage("开启离线模式"),
    "enableOfflineDescription": MessageLookupByLibrary.simpleMessage(
      "开启后会跳过在线登录校验和资料刷新，优先使用本地缓存的订阅、节点和账户摘要。",
    ),
    "enableOfflineTitle": MessageLookupByLibrary.simpleMessage("开启离线模式？"),
    "enableProxy": MessageLookupByLibrary.simpleMessage("启用"),
    "enabled": MessageLookupByLibrary.simpleMessage("已启用"),
    "enterConfirmPassword": MessageLookupByLibrary.simpleMessage("请再次输入密码"),
    "enterEmail": MessageLookupByLibrary.simpleMessage("请输入邮箱"),
    "enterEmailAddress": MessageLookupByLibrary.simpleMessage("请输入邮箱地址"),
    "enterInvitationCode": MessageLookupByLibrary.simpleMessage("请输入邀请码（如有）"),
    "enterNewPassword": MessageLookupByLibrary.simpleMessage("请输入新密码"),
    "enterOldPassword": MessageLookupByLibrary.simpleMessage("请输入旧密码"),
    "enterPassword": MessageLookupByLibrary.simpleMessage("请输入密码"),
    "enterVerificationCode": MessageLookupByLibrary.simpleMessage("请输入邮箱验证码"),
    "enterWithdrawalAccount": MessageLookupByLibrary.simpleMessage(
      "请输入对应的收款账号或地址",
    ),
    "enterWithdrawalAmount": MessageLookupByLibrary.simpleMessage("请输入提现金额"),
    "entries": MessageLookupByLibrary.simpleMessage("个条目"),
    "entriesCount": m21,
    "exclude": MessageLookupByLibrary.simpleMessage("从最近任务中隐藏"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage("应用在后台时,从最近任务中隐藏应用"),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage("排除节点过滤器"),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("排除SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "连接到被排除SSID的WIFI时，将会自动切换应用运行状态",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("排除类型"),
    "existsTip": m22,
    "exit": MessageLookupByLibrary.simpleMessage("退出"),
    "expand": MessageLookupByLibrary.simpleMessage("标准"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("预期状态"),
    "expiryEmailReminder": MessageLookupByLibrary.simpleMessage("到期邮件提醒"),
    "exportFile": MessageLookupByLibrary.simpleMessage("导出文件"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("导出日志"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("导出成功"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("表现力"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部控制器"),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "开启后将可以通过9090端口控制Clash内核",
    ),
    "externalFetch": MessageLookupByLibrary.simpleMessage("外部获取"),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部链接"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fakeip过滤"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fakeip范围"),
    "fallback": MessageLookupByLibrary.simpleMessage("Fallback"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage("一般情况下使用境外DNS"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback过滤"),
    "fastestDownload": MessageLookupByLibrary.simpleMessage("最快下载"),
    "featureComingSoon": MessageLookupByLibrary.simpleMessage("该功能将在接入服务端后启用"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("高保真"),
    "file": MessageLookupByLibrary.simpleMessage("文件"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("直接上传配置文件"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage("文件有修改，是否保存修改"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("查找进程"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage("开启后会有一定性能损耗"),
    "firstLoginAt": m23,
    "fontFamily": MessageLookupByLibrary.simpleMessage("字体"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage("您确定要强制重启核心吗？"),
    "forgotPassword": MessageLookupByLibrary.simpleMessage("忘记密码"),
    "forgotPasswordSubtitle": MessageLookupByLibrary.simpleMessage(
      "重置您的密码,恢复账号访问",
    ),
    "forgotPasswordTitle": MessageLookupByLibrary.simpleMessage("找回密码"),
    "freeLabel": MessageLookupByLibrary.simpleMessage("免费"),
    "freeOrder": MessageLookupByLibrary.simpleMessage("免费开通"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("果缤纷"),
    "general": MessageLookupByLibrary.simpleMessage("常规"),
    "generateInviteCode": MessageLookupByLibrary.simpleMessage("生成邀请码"),
    "generateMihomoRule": MessageLookupByLibrary.simpleMessage(
      "按当前连接生成 Mihomo 规则",
    ),
    "generatePaymentQr": MessageLookupByLibrary.simpleMessage("生成支付二维码"),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("自动更新"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔"),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "自动更新间隔必须大于0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geo 选项"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo 资源"),
    "geoSkipped": m24,
    "geoUpdated": m25,
    "geoUpdating": m26,
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低内存模式"),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage("开启将使用Geo低内存加载器"),
    "geodataSettings": MessageLookupByLibrary.simpleMessage("地理数据"),
    "geodataSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "更新 GeoIP 与 GeoSite 数据库",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("Geoip代码"),
    "global": MessageLookupByLibrary.simpleMessage("全局"),
    "globalAccelerationNetwork": MessageLookupByLibrary.simpleMessage("全球加速网络"),
    "globalModeWarningDescription": MessageLookupByLibrary.simpleMessage(
      "全局模式会让客户端接管的流量使用同一节点。确认后会优先沿用规则模式当前选中的节点。",
    ),
    "globalNodeDistribution": MessageLookupByLibrary.simpleMessage("全球节点分布"),
    "globalRuleModeSwitchHint": MessageLookupByLibrary.simpleMessage(
      "当前处于全局模式。添加后将切换到规则模式：此连接按上方策略处理，其余流量继续走您选择的代理策略组。",
    ),
    "go": MessageLookupByLibrary.simpleMessage("前往"),
    "goDownload": MessageLookupByLibrary.simpleMessage("前往下载"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage("前往配置脚本"),
    "halfYearBilling": MessageLookupByLibrary.simpleMessage("半年付"),
    "handlingFee": MessageLookupByLibrary.simpleMessage("手续费"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("是否缓存修改"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper 服务不可用，无法启用 TUN 模式，请重新安装 FlClash。",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("从列表中隐藏"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("隐藏密码"),
    "highestLatency": MessageLookupByLibrary.simpleMessage("最高延迟"),
    "hongKongNodesUnavailable": MessageLookupByLibrary.simpleMessage(
      "香港节点均不可用，未切换。",
    ),
    "hongKongSelectionFailed": MessageLookupByLibrary.simpleMessage(
      "节点切换失败，请重试或查看日志。",
    ),
    "host": MessageLookupByLibrary.simpleMessage("主机"),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("追加Hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("快捷键冲突"),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("快捷键管理"),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage("使用键盘控制应用程序"),
    "hours": MessageLookupByLibrary.simpleMessage("小时"),
    "hoursAgo": m27,
    "hoursCount": m28,
    "iHavePaid": MessageLookupByLibrary.simpleMessage("我已支付，刷新状态"),
    "icon": MessageLookupByLibrary.simpleMessage("图片"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("图标记录"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("图标样式"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("图标链接"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage("忽略电池优化"),
    "import": MessageLookupByLibrary.simpleMessage("导入"),
    "importFile": MessageLookupByLibrary.simpleMessage("通过文件导入"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("从URL导入"),
    "importUrl": MessageLookupByLibrary.simpleMessage("通过URL导入"),
    "inAppPayment": MessageLookupByLibrary.simpleMessage("应用内支付"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage("包含所有代理"),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "引入不包含策略组的所有代理，可在下方额外添加策略组",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage("包含所有代理集"),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "开启后将覆盖引入的代理集",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("长期有效"),
    "init": MessageLookupByLibrary.simpleMessage("初始化"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage("请输入正确的快捷键"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage("输入策略组名称"),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage("输入规则内容"),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("智能选择"),
    "internet": MessageLookupByLibrary.simpleMessage("互联网"),
    "interval": MessageLookupByLibrary.simpleMessage("间隔"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("内网 IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage("无效备份文件"),
    "invalidEmail": MessageLookupByLibrary.simpleMessage("请输入有效的邮箱地址"),
    "invalidEmailAccount": MessageLookupByLibrary.simpleMessage("请输入有效的邮箱账号"),
    "invalidPolicy": m29,
    "invalidPort": MessageLookupByLibrary.simpleMessage("请输入有效端口"),
    "invalidProxy": m30,
    "invalidProxyProvider": m31,
    "invalidSubRule": m32,
    "invitationCode": MessageLookupByLibrary.simpleMessage("邀请码"),
    "invitationCodeOptional": MessageLookupByLibrary.simpleMessage("邀请码（选填）"),
    "invitationCodeRequired": MessageLookupByLibrary.simpleMessage("请输入邀请码"),
    "inviteCode": MessageLookupByLibrary.simpleMessage("邀请码"),
    "inviteCodeDescription": MessageLookupByLibrary.simpleMessage(
      "分享专属邀请链接，好友注册并购买套餐后，您即可获得佣金奖励。",
    ),
    "inviteCodeGenerated": MessageLookupByLibrary.simpleMessage("邀请码生成成功"),
    "inviteCodeManagement": MessageLookupByLibrary.simpleMessage("邀请码管理"),
    "inviteHeroSubtitle": MessageLookupByLibrary.simpleMessage(
      "邀请越多，奖励越多，上不封顶！",
    ),
    "inviteHeroTitle": MessageLookupByLibrary.simpleMessage("邀请好友，畅享奖励"),
    "inviteLinkCopied": MessageLookupByLibrary.simpleMessage("邀请链接已复制"),
    "inviteLinkCopyFailed": MessageLookupByLibrary.simpleMessage(
      "复制邀请链接失败，请稍后重试。",
    ),
    "inviteLoadFailed": MessageLookupByLibrary.simpleMessage("邀请数据加载失败"),
    "invitePromotion": MessageLookupByLibrary.simpleMessage("邀请推广"),
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP 地址"),
    "ipLookup": MessageLookupByLibrary.simpleMessage("IP 查询"),
    "ipLookupDescription": MessageLookupByLibrary.simpleMessage(
      "查询公网 IP 的归属地、运营商等详细信息",
    ),
    "ipLookupFailed": MessageLookupByLibrary.simpleMessage(
      "IP 信息查询失败，请检查网络后重试",
    ),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IP/掩码"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage("开启后将可以接收IPv6流量"),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage("允许IPv6入站"),
    "ipv6Settings": MessageLookupByLibrary.simpleMessage("IPv6 设置"),
    "ipv6SettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "管理 Mihomo 核心 IPv6 连接能力",
    ),
    "ja": MessageLookupByLibrary.simpleMessage("日语"),
    "justNow": MessageLookupByLibrary.simpleMessage("刚刚"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage("TCP保持活动间隔"),
    "keptCount": MessageLookupByLibrary.simpleMessage("保留"),
    "key": MessageLookupByLibrary.simpleMessage("键"),
    "language": MessageLookupByLibrary.simpleMessage("语言"),
    "lastLoginAt": m33,
    "layout": MessageLookupByLibrary.simpleMessage("布局"),
    "light": MessageLookupByLibrary.simpleMessage("浅色"),
    "list": MessageLookupByLibrary.simpleMessage("列表"),
    "listen": MessageLookupByLibrary.simpleMessage("监听"),
    "listenerStartFailed": m34,
    "liveConnectionList": MessageLookupByLibrary.simpleMessage("实时连接列表"),
    "liveConnectionsCount": m35,
    "liveConnectionsFailed": MessageLookupByLibrary.simpleMessage(
      "实时连接加载失败，请稍后重试",
    ),
    "loadTest": MessageLookupByLibrary.simpleMessage("加载测试"),
    "loading": MessageLookupByLibrary.simpleMessage("加载中..."),
    "loadingPaymentMethods": MessageLookupByLibrary.simpleMessage("正在加载支付方式…"),
    "local": MessageLookupByLibrary.simpleMessage("本地"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage("备份数据到本地"),
    "locationPermission": MessageLookupByLibrary.simpleMessage("位置权限"),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "位置权限已被拒绝，无法获取当前 Wi-Fi 名称。请前往系统设置手动开启位置权限。",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "根据系统要求，获取Wi-Fi名称需要您授予位置权限。",
    ),
    "locationPermissionGuide": m36,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "需要位置权限",
    ),
    "log": MessageLookupByLibrary.simpleMessage("日志"),
    "logLevel": MessageLookupByLibrary.simpleMessage("日志等级"),
    "logcat": MessageLookupByLibrary.simpleMessage("日志捕获"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("禁用将会隐藏日志入口"),
    "loggedIn": MessageLookupByLibrary.simpleMessage("登录成功"),
    "loggingIn": MessageLookupByLibrary.simpleMessage("正在登录…"),
    "login": MessageLookupByLibrary.simpleMessage("登录"),
    "loginEndpoint": MessageLookupByLibrary.simpleMessage("登录站点"),
    "loginEndpointLabel": m37,
    "loginFailed": MessageLookupByLibrary.simpleMessage("登录失败，请稍后重试"),
    "loginIpAllowedStatus": MessageLookupByLibrary.simpleMessage("允许"),
    "loginIpBlockReason": m38,
    "loginIpBlocked": MessageLookupByLibrary.simpleMessage("登录 IP 已拉黑"),
    "loginIpBlockedStatus": MessageLookupByLibrary.simpleMessage("已拉黑"),
    "loginIpCount": MessageLookupByLibrary.simpleMessage("记录 IP"),
    "loginIpDescription": MessageLookupByLibrary.simpleMessage(
      "查看账号登录来源，并管理异常 IP。",
    ),
    "loginIpListLoadFailed": MessageLookupByLibrary.simpleMessage(
      "登录 IP 记录加载失败",
    ),
    "loginIpLoginCount": m39,
    "loginIpRecords": MessageLookupByLibrary.simpleMessage("登录 IP 记录"),
    "loginIpSecurityHint": MessageLookupByLibrary.simpleMessage(
      "拉黑只阻止该 IP 后续登录，不会中断已经登录的会话。公司、家庭或运营商共享网络可能多人共用同一个公网 IP，请确认后操作。",
    ),
    "loginIpUnblocked": MessageLookupByLibrary.simpleMessage("登录 IP 已解除限制"),
    "loginSessionExpired": MessageLookupByLibrary.simpleMessage(
      "登录状态已失效，请重新登录",
    ),
    "loginWelcome": MessageLookupByLibrary.simpleMessage("欢迎回来,请登录您的账号"),
    "logoutAccount": MessageLookupByLibrary.simpleMessage("退出登录"),
    "logoutConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "本机保存的登录信息将被清除。",
    ),
    "logoutConfirmTitle": MessageLookupByLibrary.simpleMessage("退出当前账户？"),
    "logs": MessageLookupByLibrary.simpleMessage("日志"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("日志捕获记录"),
    "logsTest": MessageLookupByLibrary.simpleMessage("日志测试"),
    "loopback": MessageLookupByLibrary.simpleMessage("回环解锁工具"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage("用于UWP回环解锁"),
    "loose": MessageLookupByLibrary.simpleMessage("宽松"),
    "lowestLatency": MessageLookupByLibrary.simpleMessage("最低延迟"),
    "manageChainProxy": MessageLookupByLibrary.simpleMessage("管理链路"),
    "manualSelection": MessageLookupByLibrary.simpleMessage("手动选择"),
    "matchContent": MessageLookupByLibrary.simpleMessage("匹配内容"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("匹配来源IP"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("最大失败次数"),
    "memberValidUntil": MessageLookupByLibrary.simpleMessage("会员有效期至"),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("内存信息"),
    "messageTest": MessageLookupByLibrary.simpleMessage("消息测试"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("这是一条消息。"),
    "min": MessageLookupByLibrary.simpleMessage("最小"),
    "mine": MessageLookupByLibrary.simpleMessage("我的"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("退出时最小化"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage("修改系统默认退出事件"),
    "minutesAgo": m40,
    "mixedPort": MessageLookupByLibrary.simpleMessage("混合端口"),
    "mixedPortSharedDescription": MessageLookupByLibrary.simpleMessage(
      "HTTP 与 SOCKS5 共用端口",
    ),
    "mode": MessageLookupByLibrary.simpleMessage("模式"),
    "modeSwitchFailed": MessageLookupByLibrary.simpleMessage(
      "模式切换失败，请重试或查看日志。",
    ),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("单色"),
    "monthlyBilling": MessageLookupByLibrary.simpleMessage("月付"),
    "monthsAgo": m41,
    "more": MessageLookupByLibrary.simpleMessage("更多"),
    "myInvitation": MessageLookupByLibrary.simpleMessage("我的邀请"),
    "myOrders": MessageLookupByLibrary.simpleMessage("我的订单"),
    "myWallet": MessageLookupByLibrary.simpleMessage("我的钱包"),
    "name": MessageLookupByLibrary.simpleMessage("名称"),
    "nameserver": MessageLookupByLibrary.simpleMessage("域名服务器"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage("用于解析域名"),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage("域名服务器策略"),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage("指定对应域名服务器策略"),
    "network": MessageLookupByLibrary.simpleMessage("网络"),
    "networkDesc": MessageLookupByLibrary.simpleMessage("修改网络相关设置"),
    "networkDetection": MessageLookupByLibrary.simpleMessage("网络检测"),
    "networkDiagnosticConfigDnsFailed": MessageLookupByLibrary.simpleMessage(
      "本地代理联网成功，但配置域名均解析失败",
    ),
    "networkDiagnosticConfigDomains": MessageLookupByLibrary.simpleMessage(
      "配置域名",
    ),
    "networkDiagnosticConfigDomainsResult": m42,
    "networkDiagnosticCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "代理内核尚未启动",
    ),
    "networkDiagnosticInternetFailed": MessageLookupByLibrary.simpleMessage(
      "通过本地代理访问外网失败",
    ),
    "networkDiagnosticInternetSuccess": MessageLookupByLibrary.simpleMessage(
      "通过本地代理访问外网成功",
    ),
    "networkDiagnosticLocalProxyPort": MessageLookupByLibrary.simpleMessage(
      "本地代理端口",
    ),
    "networkDiagnosticMode": MessageLookupByLibrary.simpleMessage("代理模式"),
    "networkDiagnosticNoProfile": MessageLookupByLibrary.simpleMessage(
      "当前没有可用订阅配置，请重新登录或刷新订阅",
    ),
    "networkDiagnosticNodeInternet": MessageLookupByLibrary.simpleMessage(
      "节点真实联网",
    ),
    "networkDiagnosticNodeUnavailable": MessageLookupByLibrary.simpleMessage(
      "本地端口正常，但当前节点无法真实联网",
    ),
    "networkDiagnosticPortListening": m43,
    "networkDiagnosticPortNotListening": MessageLookupByLibrary.simpleMessage(
      "内核已启动，但本地代理端口没有监听",
    ),
    "networkDiagnosticPortUnavailable": m44,
    "networkDiagnosticProxyFailure": m45,
    "networkDiagnosticProxyVerified": m46,
    "networkDiagnosticSelectedGroup": MessageLookupByLibrary.simpleMessage(
      "策略组",
    ),
    "networkDiagnosticSelectedNode": MessageLookupByLibrary.simpleMessage(
      "所选节点",
    ),
    "networkDiagnosticSelectionNote": MessageLookupByLibrary.simpleMessage(
      "节点信息为诊断开始时的选择；规则模式下 YouTube 可能使用其他出口。",
    ),
    "networkDiagnosticSuccess": MessageLookupByLibrary.simpleMessage(
      "本地代理及 YouTube HTTPS 访问成功；不代表视频播放、长连接或所有应用/TUN 流量均正常",
    ),
    "networkDiagnosticSystemProxyInvalid": MessageLookupByLibrary.simpleMessage(
      "Windows 系统代理未正确生效",
    ),
    "networkDiagnosticTrafficEntryMissing":
        MessageLookupByLibrary.simpleMessage("节点可用，但系统代理和虚拟网卡均未开启，应用流量不会进入内核"),
    "networkDiagnosticUnknownNode": MessageLookupByLibrary.simpleMessage(
      "未能确定所选节点",
    ),
    "networkDiagnosticWindowsSystemProxy": MessageLookupByLibrary.simpleMessage(
      "Windows 系统代理",
    ),
    "networkDiagnosticYouTube": MessageLookupByLibrary.simpleMessage(
      "YouTube HTTPS",
    ),
    "networkDiagnosticYouTubeFailed": MessageLookupByLibrary.simpleMessage(
      "基础联网检查通过，但 YouTube HTTPS 访问未通过，请检查节点或分流规则",
    ),
    "networkDiagnosticYouTubeHttpFailure": m47,
    "networkDiagnosticYouTubeNetworkFailure":
        MessageLookupByLibrary.simpleMessage("连接失败"),
    "networkDiagnosticYouTubeSuccess": m48,
    "networkDiagnosticYouTubeTimeout": MessageLookupByLibrary.simpleMessage(
      "请求超时",
    ),
    "networkDiagnosticYouTubeTlsFailure": MessageLookupByLibrary.simpleMessage(
      "TLS 握手或证书校验失败",
    ),
    "networkException": MessageLookupByLibrary.simpleMessage("网络异常，请检查连接后重试"),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("网络速度"),
    "networkType": MessageLookupByLibrary.simpleMessage("网络类型"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("中性"),
    "newPassword": MessageLookupByLibrary.simpleMessage("新密码"),
    "nextAnnouncement": MessageLookupByLibrary.simpleMessage("下一条"),
    "nextPage": MessageLookupByLibrary.simpleMessage("下一页"),
    "nextPlanResetAt": m49,
    "noActiveConnections": MessageLookupByLibrary.simpleMessage(
      "暂无活跃连接，启动 VPN 并访问网络后会显示在这里",
    ),
    "noActivePlan": MessageLookupByLibrary.simpleMessage("暂无有效套餐"),
    "noAnnouncements": MessageLookupByLibrary.simpleMessage("暂无公告"),
    "noChainProxy": MessageLookupByLibrary.simpleMessage("暂无链式代理"),
    "noChainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "添加一个 SOCKS5 或 HTTP 代理后即可管理。",
    ),
    "noCommissionRecords": MessageLookupByLibrary.simpleMessage("暂无佣金记录"),
    "noData": MessageLookupByLibrary.simpleMessage("暂无数据"),
    "noHandlingFee": MessageLookupByLibrary.simpleMessage("无手续费"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("暂无快捷键"),
    "noInfo": MessageLookupByLibrary.simpleMessage("暂无信息"),
    "noInviteCodes": MessageLookupByLibrary.simpleMessage("暂无邀请码，点击右上方按钮生成"),
    "noLimit": MessageLookupByLibrary.simpleMessage("不限"),
    "noLoginIpRecords": MessageLookupByLibrary.simpleMessage("暂无登录 IP 记录"),
    "noLongerRemind": MessageLookupByLibrary.simpleMessage("不再提示"),
    "noMatchingConnections": MessageLookupByLibrary.simpleMessage("没有找到匹配的连接"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("无网络"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("无网络应用"),
    "noOrders": MessageLookupByLibrary.simpleMessage("暂无订单记录"),
    "noPaymentMethods": MessageLookupByLibrary.simpleMessage("当前没有可用的支付方式"),
    "noPaymentRequired": MessageLookupByLibrary.simpleMessage("此订单无需付款"),
    "noProfileForRule": MessageLookupByLibrary.simpleMessage("当前没有可写入规则的订阅配置"),
    "noProxyGroupForFallback": MessageLookupByLibrary.simpleMessage(
      "当前订阅没有可用的代理策略组，无法生成全局兜底规则",
    ),
    "noRecords": MessageLookupByLibrary.simpleMessage("暂无记录"),
    "noResolve": MessageLookupByLibrary.simpleMessage("不解析IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage("不解析主机名"),
    "noSavedRules": MessageLookupByLibrary.simpleMessage("暂无已保存规则"),
    "noSavedRulesDescription": MessageLookupByLibrary.simpleMessage(
      "可从当前连接添加规则，也可以在这里直接创建",
    ),
    "noSuccessfulLogin": MessageLookupByLibrary.simpleMessage("尚未产生成功登录"),
    "noTrafficRecords": MessageLookupByLibrary.simpleMessage("本月暂无流量记录"),
    "nodeAvailable": MessageLookupByLibrary.simpleMessage("可用"),
    "nodeBackendOffline": MessageLookupByLibrary.simpleMessage("后台离线"),
    "nodeBackendOnline": MessageLookupByLibrary.simpleMessage("后台在线"),
    "nodeLabel": MessageLookupByLibrary.simpleMessage("节点"),
    "nodeLocallyUnreachable": MessageLookupByLibrary.simpleMessage("当前网络不可达"),
    "nodeNetworkFluctuating": MessageLookupByLibrary.simpleMessage("网络波动"),
    "nodeStatus": MessageLookupByLibrary.simpleMessage("节点状态"),
    "nodeStatusSubtitle": MessageLookupByLibrary.simpleMessage(
      "选择最优节点，畅享极速稳定的网络连接",
    ),
    "nodeStatusUnknown": MessageLookupByLibrary.simpleMessage("状态未知"),
    "nodeUpdateSuccess": MessageLookupByLibrary.simpleMessage("已获取最新节点信息"),
    "nodesCount": m50,
    "none": MessageLookupByLibrary.simpleMessage("无"),
    "notEnabled": MessageLookupByLibrary.simpleMessage("未开启"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage("当前代理组无法选中"),
    "notTested": MessageLookupByLibrary.simpleMessage("未测速"),
    "notificationSettings": MessageLookupByLibrary.simpleMessage("通知设置"),
    "notificationSettingsSaved": MessageLookupByLibrary.simpleMessage(
      "通知设置已保存",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage("没有配置文件,请先添加配置文件"),
    "nullTip": m51,
    "numberTip": m52,
    "offline": MessageLookupByLibrary.simpleMessage("离线"),
    "offlineCacheContinues": MessageLookupByLibrary.simpleMessage(
      "已有缓存会继续用于首页和节点展示。",
    ),
    "offlineCacheUnavailable": MessageLookupByLibrary.simpleMessage(
      "本机没有三天内验证过的有效订阅缓存",
    ),
    "offlineEntry": MessageLookupByLibrary.simpleMessage("使用本地缓存进入"),
    "offlineEntryHint": MessageLookupByLibrary.simpleMessage(
      "使用最近一次验证的订阅与节点配置",
    ),
    "offlineEntryUnavailable": MessageLookupByLibrary.simpleMessage(
      "暂无可用的离线缓存",
    ),
    "offlineMode": MessageLookupByLibrary.simpleMessage("离线模式"),
    "offlineModeBanner": MessageLookupByLibrary.simpleMessage(
      "离线模式已开启，当前显示本地缓存数据",
    ),
    "offlineModeDescriptionTitle": MessageLookupByLibrary.simpleMessage(
      "离线模式说明",
    ),
    "offlineModeEnabled": MessageLookupByLibrary.simpleMessage("已开启"),
    "offlineNetworkTools": MessageLookupByLibrary.simpleMessage(
      "不依赖账户登录的网络工具仍可正常使用。",
    ),
    "offlineNoUpdates": MessageLookupByLibrary.simpleMessage(
      "不会获取新的套餐、邀请、订阅和用户资料。",
    ),
    "oldPassword": MessageLookupByLibrary.simpleMessage("旧密码"),
    "onDemand": MessageLookupByLibrary.simpleMessage("按需运行"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage("配置程序特定场景运行状态"),
    "oneTimeBilling": MessageLookupByLibrary.simpleMessage("一次性"),
    "oneTimePlans": MessageLookupByLibrary.simpleMessage("一次性"),
    "online": MessageLookupByLibrary.simpleMessage("在线"),
    "onlineFeaturesUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "该功能需要恢复在线模式后使用",
    ),
    "onlineSupport": MessageLookupByLibrary.simpleMessage("在线客服"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("仅图标"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage("仅统计代理"),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "开启后，将只统计代理流量",
    ),
    "optimizationComplete": MessageLookupByLibrary.simpleMessage("优选完成"),
    "optimizationDownload": MessageLookupByLibrary.simpleMessage("正在测试下载速度"),
    "optimizationFailed": MessageLookupByLibrary.simpleMessage(
      "没有找到可用的 Cloudflare IP，请检查网络后重试",
    ),
    "optimizationLatency": MessageLookupByLibrary.simpleMessage("正在测试连接延迟"),
    "optimizationPreparing": MessageLookupByLibrary.simpleMessage(
      "正在加载 Cloudflare 候选 IP",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("可选"),
    "options": MessageLookupByLibrary.simpleMessage("选项"),
    "orderAmount": MessageLookupByLibrary.simpleMessage("金额"),
    "orderCancelled": MessageLookupByLibrary.simpleMessage("订单已取消"),
    "orderCancelledSuccess": MessageLookupByLibrary.simpleMessage("订单已取消"),
    "orderCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "查看套餐与流量重置订单，掌握支付和开通状态",
    ),
    "orderDetailsTitle": MessageLookupByLibrary.simpleMessage("订单详情"),
    "orderListFailed": MessageLookupByLibrary.simpleMessage("订单列表加载失败"),
    "orderNumber": MessageLookupByLibrary.simpleMessage("订单号"),
    "orderPageIndicator": m53,
    "orderPeriod": MessageLookupByLibrary.simpleMessage("周期"),
    "orderPlan": MessageLookupByLibrary.simpleMessage("套餐"),
    "orderStatusCancelled": MessageLookupByLibrary.simpleMessage("已取消"),
    "orderStatusCompleted": MessageLookupByLibrary.simpleMessage("已完成"),
    "orderStatusPending": MessageLookupByLibrary.simpleMessage("待支付"),
    "orderStatusProcessing": MessageLookupByLibrary.simpleMessage("开通中"),
    "orderStatusUnknown": MessageLookupByLibrary.simpleMessage("未知状态"),
    "organization": MessageLookupByLibrary.simpleMessage("组织"),
    "other": MessageLookupByLibrary.simpleMessage("其他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("其他贡献者"),
    "otherTrafficPolicy": MessageLookupByLibrary.simpleMessage("其他流量策略"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("出站模式"),
    "override": MessageLookupByLibrary.simpleMessage("覆写"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("覆写DNS"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage("开启后将覆盖配置中的DNS选项"),
    "overrideMode": MessageLookupByLibrary.simpleMessage("覆写模式"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("覆写脚本"),
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("自定义"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "自定义模式，支持完全自定义修改代理组以及规则",
    ),
    "paidAt": MessageLookupByLibrary.simpleMessage("支付时间"),
    "palette": MessageLookupByLibrary.simpleMessage("调色板"),
    "password": MessageLookupByLibrary.simpleMessage("密码"),
    "passwordChanged": MessageLookupByLibrary.simpleMessage("密码修改成功"),
    "passwordResetFailed": MessageLookupByLibrary.simpleMessage("密码重置失败，请稍后重试"),
    "passwordResetSuccess": MessageLookupByLibrary.simpleMessage(
      "密码重置成功，请使用新密码登录",
    ),
    "passwordTooShort": MessageLookupByLibrary.simpleMessage("密码至少需要8位"),
    "passwordsDoNotMatch": MessageLookupByLibrary.simpleMessage("两次输入的密码不一致"),
    "paste": MessageLookupByLibrary.simpleMessage("粘贴"),
    "paymentFailed": MessageLookupByLibrary.simpleMessage("支付未完成"),
    "paymentMethod": MessageLookupByLibrary.simpleMessage("支付方式"),
    "paymentSecurityHint": MessageLookupByLibrary.simpleMessage(
      "订单与二维码均由 XBoard 支付接口实时生成",
    ),
    "paymentStaysInApp": MessageLookupByLibrary.simpleMessage(
      "支付二维码将在客户端内安全展示",
    ),
    "paymentSuccessful": MessageLookupByLibrary.simpleMessage("支付成功"),
    "paymentSuccessfulHint": MessageLookupByLibrary.simpleMessage(
      "套餐正在开通，请稍后刷新订阅",
    ),
    "payoutTime": MessageLookupByLibrary.simpleMessage("发放时间"),
    "pendingCommission": MessageLookupByLibrary.simpleMessage("确认中的佣金"),
    "pendingTest": MessageLookupByLibrary.simpleMessage("待检测"),
    "peopleCount": m54,
    "personalCenter": MessageLookupByLibrary.simpleMessage("个人中心"),
    "planCatalogEmpty": MessageLookupByLibrary.simpleMessage("暂无可购买的套餐"),
    "planCatalogFailed": MessageLookupByLibrary.simpleMessage("套餐加载失败"),
    "planDevicesLabel": MessageLookupByLibrary.simpleMessage("设备"),
    "planSpeedLabel": MessageLookupByLibrary.simpleMessage("速率"),
    "planStoreSubtitle": MessageLookupByLibrary.simpleMessage(
      "安全连接全球网络，极速稳定，畅享无限可能",
    ),
    "planTrafficLabel": MessageLookupByLibrary.simpleMessage("流量"),
    "platformCount": MessageLookupByLibrary.simpleMessage("平台"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage("请绑定WebDAV"),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage("请输入脚本名称"),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "请输入管理员密码",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "请上传有效的二维码",
    ),
    "pleaseWait": MessageLookupByLibrary.simpleMessage("请稍候，不要重复提交"),
    "popularApps": MessageLookupByLibrary.simpleMessage("热门应用"),
    "popularAppsDescription": MessageLookupByLibrary.simpleMessage(
      "查看常用客户端和辅助应用列表",
    ),
    "port": MessageLookupByLibrary.simpleMessage("端口"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("请输入不同的端口"),
    "portTip": m55,
    "practicalTools": MessageLookupByLibrary.simpleMessage("实用工具"),
    "practicalToolsSubtitle": MessageLookupByLibrary.simpleMessage(
      "常用网络辅助工具，帮你更高效地使用网络服务",
    ),
    "preferH3Desc": MessageLookupByLibrary.simpleMessage("优先使用DOH的http/3"),
    "preferredNodes": MessageLookupByLibrary.simpleMessage("优选节点"),
    "prerequisites": MessageLookupByLibrary.simpleMessage("前置条件"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("请按下按键"),
    "preview": MessageLookupByLibrary.simpleMessage("预览"),
    "previousAnnouncement": MessageLookupByLibrary.simpleMessage("上一条"),
    "previousPage": MessageLookupByLibrary.simpleMessage("上一页"),
    "process": MessageLookupByLibrary.simpleMessage("进程"),
    "profile": MessageLookupByLibrary.simpleMessage("配置"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入有效间隔时间格式"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入自动更新间隔时间"),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "配置文件已经修改,是否关闭自动更新 ",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置名称",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入有效配置URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("配置"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("配置排序"),
    "project": MessageLookupByLibrary.simpleMessage("项目"),
    "protocolLabel": MessageLookupByLibrary.simpleMessage("协议"),
    "providers": MessageLookupByLibrary.simpleMessage("提供者"),
    "provinceCity": MessageLookupByLibrary.simpleMessage("省份/城市"),
    "proxies": MessageLookupByLibrary.simpleMessage("代理"),
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("代理为空"),
    "proxyAccessAddress": MessageLookupByLibrary.simpleMessage("本地代理地址"),
    "proxyChains": MessageLookupByLibrary.simpleMessage("代理链"),
    "proxyDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "检测到选中的代理存在异常",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("节点过滤器"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("策略组"),
    "proxyGroupDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "检测到当前策略组异常",
    ),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage("策略组为空"),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage("策略组名称重复"),
    "proxyGroupNameEmpty": MessageLookupByLibrary.simpleMessage("策略组名称不能为空"),
    "proxyNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "代理名称已存在，请使用其他名称",
    ),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("代理域名服务器"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage("用于解析代理节点的域名"),
    "proxyNeededChooseNode": MessageLookupByLibrary.simpleMessage(
      "如果目标模式不包含该节点，将保留目标模式原来的节点选择。",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("代理端口"),
    "proxyProtocolMismatch": MessageLookupByLibrary.simpleMessage(
      "协议类型不正确，检测到应为",
    ),
    "proxyProviderDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "检测到选中的代理集存在异常",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("代理集"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage("代理集为空"),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage("代理集不能为空"),
    "proxyServer": MessageLookupByLibrary.simpleMessage("服务器"),
    "proxySettings": MessageLookupByLibrary.simpleMessage("代理设置"),
    "proxySettingsSubtitle": MessageLookupByLibrary.simpleMessage("管理本地代理服务"),
    "proxyType": MessageLookupByLibrary.simpleMessage("代理类型"),
    "proxyValidationFailed": MessageLookupByLibrary.simpleMessage(
      "代理无法连通，请检查服务器、端口、账号和密码",
    ),
    "pruneCache": MessageLookupByLibrary.simpleMessage("修剪缓存"),
    "publicIp": MessageLookupByLibrary.simpleMessage("公网 IP"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("购买套餐"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("纯黑模式"),
    "qrcode": MessageLookupByLibrary.simpleMessage("二维码"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage("扫描二维码获取配置文件"),
    "qualityNodes": MessageLookupByLibrary.simpleMessage("优质节点"),
    "quarterlyBilling": MessageLookupByLibrary.simpleMessage("季付"),
    "queryNow": MessageLookupByLibrary.simpleMessage("立即查询"),
    "quickFill": MessageLookupByLibrary.simpleMessage("一键填入"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("彩虹"),
    "reachable": MessageLookupByLibrary.simpleMessage("可连接"),
    "realTimeConnections": MessageLookupByLibrary.simpleMessage("代理规则"),
    "realTimeConnectionsSubtitle": MessageLookupByLibrary.simpleMessage(
      "查看当前网络连接并管理自定义分流规则",
    ),
    "recurringPlans": MessageLookupByLibrary.simpleMessage("周期性"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir端口"),
    "redo": MessageLookupByLibrary.simpleMessage("重做"),
    "referenceConnectionDelay": MessageLookupByLibrary.simpleMessage("参考连接延迟"),
    "referenceCurrentNodeDelay": MessageLookupByLibrary.simpleMessage("参考节点延迟"),
    "referenceDelayExplanation": MessageLookupByLibrary.simpleMessage(
      "显示校准后的完整线路参考延迟；测速失败显示“超时”。",
    ),
    "referenceDelayValue": m56,
    "referenceStandardizedDelay": MessageLookupByLibrary.simpleMessage(
      "参考标准 RTT",
    ),
    "refreshApiStatus": MessageLookupByLibrary.simpleMessage("刷新 API 连通状态"),
    "refreshConfiguration": MessageLookupByLibrary.simpleMessage("刷新配置"),
    "refreshData": MessageLookupByLibrary.simpleMessage("刷新数据"),
    "refreshNodes": MessageLookupByLibrary.simpleMessage("刷新"),
    "refreshSubscription": MessageLookupByLibrary.simpleMessage("刷新订阅"),
    "region": MessageLookupByLibrary.simpleMessage("地区"),
    "registerAccount": MessageLookupByLibrary.simpleMessage("注册账号"),
    "registerAction": MessageLookupByLibrary.simpleMessage("注册"),
    "registeredUsers": MessageLookupByLibrary.simpleMessage("已注册用户数"),
    "registrationApiPending": MessageLookupByLibrary.simpleMessage("注册接口待接入"),
    "registrationClosed": MessageLookupByLibrary.simpleMessage("当前已停止新用户注册"),
    "registrationFailed": MessageLookupByLibrary.simpleMessage("注册失败，请稍后重试"),
    "registrationSuccess": MessageLookupByLibrary.simpleMessage("注册成功"),
    "reject": MessageLookupByLibrary.simpleMessage("拦截"),
    "remainingCommission": MessageLookupByLibrary.simpleMessage("当前剩余佣金"),
    "remainingTraffic": MessageLookupByLibrary.simpleMessage("剩余流量"),
    "remainingTrafficLabel": MessageLookupByLibrary.simpleMessage("剩余"),
    "rememberMe": MessageLookupByLibrary.simpleMessage("记住我"),
    "rememberedLoginClearFailed": MessageLookupByLibrary.simpleMessage(
      "未能完整清除或禁用已保存的登录信息，请重试。",
    ),
    "rememberedLoginHint": MessageLookupByLibrary.simpleMessage("已记住，可直接登录"),
    "rememberedLoginSaveFailed": MessageLookupByLibrary.simpleMessage(
      "登录成功，但未能安全保存登录凭证，下次仍需输入密码",
    ),
    "rememberedPassword": MessageLookupByLibrary.simpleMessage("记起密码了？"),
    "remote": MessageLookupByLibrary.simpleMessage("远程"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage("备份数据到WebDAV"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage("远程目标"),
    "remove": MessageLookupByLibrary.simpleMessage("移除"),
    "rename": MessageLookupByLibrary.simpleMessage("重命名"),
    "renewPlanAction": MessageLookupByLibrary.simpleMessage("续费"),
    "renewalDoesNotResetTraffic": MessageLookupByLibrary.simpleMessage(
      "续费订单只会延长套餐有效期，不会重置当前已使用流量。若需要恢复套餐流量，请选择“重置流量”。",
    ),
    "renewalNoticeTitle": MessageLookupByLibrary.simpleMessage("续费说明"),
    "renewalUnavailable": MessageLookupByLibrary.simpleMessage("当前套餐暂不支持续费"),
    "request": MessageLookupByLibrary.simpleMessage("请求"),
    "requestFailed": MessageLookupByLibrary.simpleMessage("请求失败，请稍后重试"),
    "requests": MessageLookupByLibrary.simpleMessage("请求"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage("查看最近请求记录"),
    "requiredField": MessageLookupByLibrary.simpleMessage("此项不能为空"),
    "rerunOptimization": MessageLookupByLibrary.simpleMessage("重新优选"),
    "reset": MessageLookupByLibrary.simpleMessage("重置"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "当前页面存在更改，确定重置吗？",
    ),
    "resetPasswordAction": MessageLookupByLibrary.simpleMessage("重置密码"),
    "resetSubscription": MessageLookupByLibrary.simpleMessage("重置订阅信息"),
    "resetSubscriptionConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "原订阅地址将立即失效，所有设备都需要重新同步订阅。",
    ),
    "resetSubscriptionConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "确定重置订阅吗？",
    ),
    "resetSubscriptionDescription": MessageLookupByLibrary.simpleMessage(
      "订阅泄漏或异常时，可重新生成订阅地址",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("确定要重置吗?"),
    "resetTrafficAction": MessageLookupByLibrary.simpleMessage("重置流量"),
    "resettingPassword": MessageLookupByLibrary.simpleMessage("正在重置…"),
    "resources": MessageLookupByLibrary.simpleMessage("资源"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage("外部资源相关信息"),
    "respectRules": MessageLookupByLibrary.simpleMessage("遵守规则"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS连接跟随rules,需配置proxy-server-nameserver",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("重启"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage("您确定要重启核心吗？"),
    "restore": MessageLookupByLibrary.simpleMessage("恢复"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("恢复所有数据"),
    "restoreException": MessageLookupByLibrary.simpleMessage("恢复异常"),
    "restoreFromFileDesc": MessageLookupByLibrary.simpleMessage("通过文件恢复数据"),
    "restoreFromWebDAVDesc": MessageLookupByLibrary.simpleMessage(
      "通过WebDAV恢复数据",
    ),
    "restoreOnline": MessageLookupByLibrary.simpleMessage("恢复在线模式"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage("仅恢复配置文件"),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("恢复策略"),
    "restoreStrategy_compatible": MessageLookupByLibrary.simpleMessage("兼容"),
    "restoreStrategy_override": MessageLookupByLibrary.simpleMessage("覆盖"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage("恢复成功"),
    "restoringOnline": MessageLookupByLibrary.simpleMessage("正在恢复在线模式…"),
    "retry": MessageLookupByLibrary.simpleMessage("重试"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("路由地址"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage("配置监听路由地址"),
    "routeMode": MessageLookupByLibrary.simpleMessage("路由模式"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage("绕过私有路由地址"),
    "routeMode_config": MessageLookupByLibrary.simpleMessage("使用配置"),
    "ru": MessageLookupByLibrary.simpleMessage("俄语"),
    "rule": MessageLookupByLibrary.simpleMessage("规则"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 AND"),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage("匹配完整域名"),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "匹配域名关键字",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配域名后缀",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "匹配DSCP标记 (仅限 tproxy udp 入站)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage("匹配请求目标端口范围"),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 所属国家代码"),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 Geosite 内的域名",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage("匹配入站名称"),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage("匹配入站端口"),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage("匹配入站类型"),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "匹配入站用户名，支持使用 / 分隔多个用户名",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 所属 ASN"),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "匹配 IP 地址范围, IP-CIDR6 只是一个别名",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 地址范围"),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 IP 后缀范围",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage("匹配所有请求，无需条件"),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage("匹配TCP或者UDP"),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 NOT"),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程匹配，在Android平台可以匹配包名",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程名称正则表达式匹配，在Android平台可以匹配包名",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "使用完整进程路径匹配",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程路径正则表达式匹配",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "引用规则集合，需配置rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 所属国家代码",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 所属 ASN",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 地址范围",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 后缀范围",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage("匹配请求来源端口范围"),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "匹配至子规则,需要注意括号的使用",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("规则为空"),
    "ruleName": MessageLookupByLibrary.simpleMessage("规则名称"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("规则集"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("规则集"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("规则目标"),
    "ruleType": MessageLookupByLibrary.simpleMessage("规则类型"),
    "ruleTypeHelp": MessageLookupByLibrary.simpleMessage(
      "DOMAIN 匹配完整域名，DOMAIN-SUFFIX 同时匹配其子域名",
    ),
    "runNetworkDiagnostics": MessageLookupByLibrary.simpleMessage("一键网络诊断"),
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("保存修改"),
    "savedDnsServersCount": m57,
    "savedRuleDeleted": MessageLookupByLibrary.simpleMessage("规则已删除，配置已重新应用"),
    "savedRuleDisabled": MessageLookupByLibrary.simpleMessage("规则已停用并生效"),
    "savedRuleEnabled": MessageLookupByLibrary.simpleMessage("规则已启用并生效"),
    "savedRuleUpdated": MessageLookupByLibrary.simpleMessage("规则已修改并生效"),
    "savedRules": MessageLookupByLibrary.simpleMessage("已保存规则"),
    "savedRulesAccountHint": MessageLookupByLibrary.simpleMessage(
      "规则仅保存在此设备，退出登录后保留，同账号再次登录自动恢复",
    ),
    "savedRulesAccountScope": MessageLookupByLibrary.simpleMessage("当前账号的本地规则"),
    "savedRulesLoadFailed": MessageLookupByLibrary.simpleMessage("已保存规则加载失败"),
    "savedRulesLoadFailedDescription": MessageLookupByLibrary.simpleMessage(
      "请检查本地订阅数据后重试",
    ),
    "savedRulesOrderHint": MessageLookupByLibrary.simpleMessage(
      "规则从上到下匹配，可拖动调整优先级",
    ),
    "savedRulesProfileHint": MessageLookupByLibrary.simpleMessage(
      "切换订阅后，将显示该订阅对应的规则",
    ),
    "savedRulesProfileScope": m58,
    "savedRulesReordered": MessageLookupByLibrary.simpleMessage("规则优先级已更新并生效"),
    "savedRulesRequireProfile": MessageLookupByLibrary.simpleMessage(
      "请先选择订阅，再添加或管理规则",
    ),
    "scanToPay": MessageLookupByLibrary.simpleMessage("扫码支付"),
    "scanWithPaymentApp": MessageLookupByLibrary.simpleMessage(
      "请使用对应的支付应用扫描下方二维码",
    ),
    "script": MessageLookupByLibrary.simpleMessage("脚本"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "脚本模式，使用外部扩展脚本，提供一键覆写配置的能力",
    ),
    "search": MessageLookupByLibrary.simpleMessage("搜索"),
    "searchConnectionsHint": MessageLookupByLibrary.simpleMessage(
      "搜索域名、IP、规则或节点",
    ),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "secondsCount": m59,
    "selectAll": MessageLookupByLibrary.simpleMessage("全选"),
    "selectPaymentMethod": MessageLookupByLibrary.simpleMessage("选择支付方式"),
    "selectProxies": MessageLookupByLibrary.simpleMessage("选择代理"),
    "selectProxyGroup": MessageLookupByLibrary.simpleMessage("选择代理策略组"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage("选择代理集"),
    "selectRenewalPeriod": MessageLookupByLibrary.simpleMessage("选择续费周期"),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage("请选择规则集"),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage("请选择分流策略"),
    "selectSubRule": MessageLookupByLibrary.simpleMessage("请选择子规则"),
    "selectWithdrawalMethod": MessageLookupByLibrary.simpleMessage("请选择提现方式"),
    "selected": MessageLookupByLibrary.simpleMessage("已选择"),
    "selectedCountTitle": m60,
    "sendVerificationCode": MessageLookupByLibrary.simpleMessage("发送"),
    "sendingVerificationCode": MessageLookupByLibrary.simpleMessage("发送中..."),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("服务状态"),
    "settings": MessageLookupByLibrary.simpleMessage("设置"),
    "show": MessageLookupByLibrary.simpleMessage("显示"),
    "showPassword": MessageLookupByLibrary.simpleMessage("显示密码"),
    "shrink": MessageLookupByLibrary.simpleMessage("紧凑"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("静默启动"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "启动时隐藏主窗口，可从系统托盘打开。",
    ),
    "size": MessageLookupByLibrary.simpleMessage("尺寸"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks端口"),
    "softwareUpdate": MessageLookupByLibrary.simpleMessage("软件更新"),
    "soldOut": MessageLookupByLibrary.simpleMessage("已售罄"),
    "sort": MessageLookupByLibrary.simpleMessage("排序"),
    "source": MessageLookupByLibrary.simpleMessage("来源"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("源IP"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("特殊代理"),
    "specialRules": MessageLookupByLibrary.simpleMessage("特殊规则"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("网速统计"),
    "speedTest": MessageLookupByLibrary.simpleMessage("网速测试"),
    "speedTestDescription": MessageLookupByLibrary.simpleMessage(
      "选择第三方测速网站测试当前网络速度",
    ),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("分流策略"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage("分流策略不能为空"),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs为空"),
    "stackMode": MessageLookupByLibrary.simpleMessage("栈模式"),
    "standard": MessageLookupByLibrary.simpleMessage("标准"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "标准模式，覆写基本配置，提供简单追加规则能力",
    ),
    "standardizedDelay": MessageLookupByLibrary.simpleMessage("标准 RTT"),
    "start": MessageLookupByLibrary.simpleMessage("启动"),
    "startAcceleration": MessageLookupByLibrary.simpleMessage("开始加速"),
    "startOptimization": MessageLookupByLibrary.simpleMessage("开始优选"),
    "startTest": MessageLookupByLibrary.simpleMessage("开始检测"),
    "startVpn": MessageLookupByLibrary.simpleMessage("正在启动VPN..."),
    "startupSettings": MessageLookupByLibrary.simpleMessage("启动设置"),
    "startupSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "设置此设备上的程序启动方式",
    ),
    "status": MessageLookupByLibrary.simpleMessage("状态"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("关闭后将使用系统DNS"),
    "stop": MessageLookupByLibrary.simpleMessage("暂停"),
    "stopAcceleration": MessageLookupByLibrary.simpleMessage("停止加速"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("正在停止VPN..."),
    "streamingExitRegion": MessageLookupByLibrary.simpleMessage("出口地区"),
    "streamingFailed": MessageLookupByLibrary.simpleMessage("连接失败"),
    "streamingNetworkError": MessageLookupByLibrary.simpleMessage("网络连接失败"),
    "streamingProxyRequired": MessageLookupByLibrary.simpleMessage(
      "请先启动加速并选择代理节点后再检测",
    ),
    "streamingReachable": MessageLookupByLibrary.simpleMessage("网页可访问，深度状态未确认"),
    "streamingReachableProbeFailed": MessageLookupByLibrary.simpleMessage(
      "网页可访问，深度状态未确认",
    ),
    "streamingReachableProbeTimedOut": MessageLookupByLibrary.simpleMessage(
      "网页可访问，深度检测超时",
    ),
    "streamingRestricted": MessageLookupByLibrary.simpleMessage("地区受限"),
    "streamingServiceError": MessageLookupByLibrary.simpleMessage("服务暂时异常"),
    "streamingTimedOut": MessageLookupByLibrary.simpleMessage("检测超时，请重试"),
    "streamingUnlockTest": MessageLookupByLibrary.simpleMessage("流媒体解锁检测"),
    "streamingUnlockTestDescription": MessageLookupByLibrary.simpleMessage(
      "检测当前节点对流媒体和 AI 服务的可用状态",
    ),
    "streamingUnlocked": MessageLookupByLibrary.simpleMessage("网页可访问"),
    "style": MessageLookupByLibrary.simpleMessage("风格"),
    "subRule": MessageLookupByLibrary.simpleMessage("子规则"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("子规则为空"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage("子规则不能为空"),
    "submit": MessageLookupByLibrary.simpleMessage("提交"),
    "submitWithdrawalTicket": MessageLookupByLibrary.simpleMessage("提交提现工单"),
    "subscriptionExpiredWarning": m61,
    "subscriptionExpiringWarning": m62,
    "subscriptionImportFailed": MessageLookupByLibrary.simpleMessage(
      "订阅节点加载失败，请检查网络后重试",
    ),
    "subscriptionLowTrafficWarning": m63,
    "subscriptionNormalTooltip": MessageLookupByLibrary.simpleMessage(
      "套餐状态正常，点击查看详情",
    ),
    "subscriptionPlanUnavailable": MessageLookupByLibrary.simpleMessage(
      "未找到当前套餐信息，请刷新后重试",
    ),
    "subscriptionResetContinue": MessageLookupByLibrary.simpleMessage("继续重置"),
    "subscriptionResetCountdown": m64,
    "subscriptionResetExpired": MessageLookupByLibrary.simpleMessage(
      "套餐已过期，请先续费，重置安排以续费后的套餐信息为准。",
    ),
    "subscriptionResetNoSchedule": MessageLookupByLibrary.simpleMessage(
      "当前套餐无周期重置日期。",
    ),
    "subscriptionResetNoticeTitle": MessageLookupByLibrary.simpleMessage(
      "流量重置说明",
    ),
    "subscriptionResetScheduleUnavailable":
        MessageLookupByLibrary.simpleMessage("暂未获取有效的下次重置日期，请刷新套餐信息。"),
    "subscriptionResetSuccess": MessageLookupByLibrary.simpleMessage(
      "订阅已重置并重新同步",
    ),
    "subscriptionResetWithinDay": m65,
    "subscriptionStatusNormalMessage": MessageLookupByLibrary.simpleMessage(
      "当前套餐剩余流量和有效期均处于正常状态。",
    ),
    "subscriptionStatusNormalTitle": MessageLookupByLibrary.simpleMessage(
      "套餐状态正常",
    ),
    "subscriptionTrafficExpiresAtReset": MessageLookupByLibrary.simpleMessage(
      "本周期剩余流量将在下次重置日作废，不结转。",
    ),
    "subscriptionUpgradeNotice": MessageLookupByLibrary.simpleMessage(
      "升级套餐生效后将覆盖当前套餐，是否继续前往商城？",
    ),
    "subscriptionWarningTitle": MessageLookupByLibrary.simpleMessage("套餐预警"),
    "subscriptionWarningTooltip": MessageLookupByLibrary.simpleMessage(
      "套餐存在预警，点击查看详情",
    ),
    "supportLoadFailed": MessageLookupByLibrary.simpleMessage(
      "客服页面加载失败，请重试或在浏览器中打开。",
    ),
    "supportLoadingSlow": MessageLookupByLibrary.simpleMessage(
      "客服页面加载较慢，可以继续等待、重试或在浏览器中打开。",
    ),
    "supportOpenBrowser": MessageLookupByLibrary.simpleMessage("浏览器打开"),
    "supportOpenBrowserFailed": MessageLookupByLibrary.simpleMessage(
      "无法打开浏览器，请重试。",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("挂起中..."),
    "switchAndKeepCurrentNode": MessageLookupByLibrary.simpleMessage(
      "沿用当前节点并切换",
    ),
    "switchNode": MessageLookupByLibrary.simpleMessage("切换节点"),
    "switchToGlobalMode": MessageLookupByLibrary.simpleMessage("切换到全局模式"),
    "sync": MessageLookupByLibrary.simpleMessage("同步"),
    "syncingCurrentNodeForModeSwitch": MessageLookupByLibrary.simpleMessage(
      "正在同步当前节点并切换模式…",
    ),
    "system": MessageLookupByLibrary.simpleMessage("系统"),
    "systemApp": MessageLookupByLibrary.simpleMessage("系统应用"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "systemProxyApplyFailed": m66,
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage("设置系统代理"),
    "systemProxyDisableFailed": m67,
    "systemProxyStaleCleaned": MessageLookupByLibrary.simpleMessage(
      "已清理上次异常退出残留的系统代理",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("标签页"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("选项卡动画"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage("仅在移动视图中有效"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("点击授权"),
    "targetPolicy": MessageLookupByLibrary.simpleMessage("目标策略"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP并发"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage("开启后允许TCP并发"),
    "telegramBinding": MessageLookupByLibrary.simpleMessage("Telegram 绑定"),
    "telegramId": MessageLookupByLibrary.simpleMessage("Telegram ID"),
    "telegramUnboundHint": MessageLookupByLibrary.simpleMessage(
      "当前账户尚未绑定 Telegram",
    ),
    "testAll": MessageLookupByLibrary.simpleMessage("全部检测"),
    "testAllEndpoints": MessageLookupByLibrary.simpleMessage("全部测速"),
    "testEndpoint": MessageLookupByLibrary.simpleMessage("测速"),
    "testInterval": MessageLookupByLibrary.simpleMessage("测试间隔"),
    "testUrl": MessageLookupByLibrary.simpleMessage("测速链接"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("使用时测试"),
    "testingStatus": MessageLookupByLibrary.simpleMessage("检测中"),
    "textScale": MessageLookupByLibrary.simpleMessage("文本缩放"),
    "theme": MessageLookupByLibrary.simpleMessage("主题"),
    "themeColor": MessageLookupByLibrary.simpleMessage("主题色彩"),
    "themeDesc": MessageLookupByLibrary.simpleMessage("设置深色模式，调整色彩"),
    "themeMode": MessageLookupByLibrary.simpleMessage("主题模式"),
    "threeYearBilling": MessageLookupByLibrary.simpleMessage("三年付"),
    "ticketActionFailed": MessageLookupByLibrary.simpleMessage(
      "操作失败，已保留输入内容，请重试",
    ),
    "ticketClose": MessageLookupByLibrary.simpleMessage("关闭工单"),
    "ticketCloseConfirm": MessageLookupByLibrary.simpleMessage(
      "确定关闭此工单？关闭后将无法继续回复。",
    ),
    "ticketClosed": MessageLookupByLibrary.simpleMessage("已关闭"),
    "ticketContent": MessageLookupByLibrary.simpleMessage("请描述遇到的问题"),
    "ticketCreated": MessageLookupByLibrary.simpleMessage("工单已提交"),
    "ticketEmpty": MessageLookupByLibrary.simpleMessage("暂无此类工单"),
    "ticketHigh": MessageLookupByLibrary.simpleMessage("高"),
    "ticketList": MessageLookupByLibrary.simpleMessage("工单列表"),
    "ticketLoadFailed": MessageLookupByLibrary.simpleMessage("工单加载失败，请重试"),
    "ticketLow": MessageLookupByLibrary.simpleMessage("低"),
    "ticketMore": MessageLookupByLibrary.simpleMessage("加载更多"),
    "ticketNew": MessageLookupByLibrary.simpleMessage("提交工单"),
    "ticketNormal": MessageLookupByLibrary.simpleMessage("中"),
    "ticketOpen": MessageLookupByLibrary.simpleMessage("开启中"),
    "ticketPriority": MessageLookupByLibrary.simpleMessage("优先级"),
    "ticketReadFailed": MessageLookupByLibrary.simpleMessage(
      "已读状态同步失败，请重试以清除提醒",
    ),
    "ticketRefresh": MessageLookupByLibrary.simpleMessage("刷新"),
    "ticketReplied": MessageLookupByLibrary.simpleMessage("已回复"),
    "ticketReply": MessageLookupByLibrary.simpleMessage("回复"),
    "ticketReplyHint": MessageLookupByLibrary.simpleMessage("输入回复内容"),
    "ticketRequired": MessageLookupByLibrary.simpleMessage("请填写此项"),
    "ticketSubject": MessageLookupByLibrary.simpleMessage("工单主题"),
    "ticketSubmit": MessageLookupByLibrary.simpleMessage("提交工单"),
    "ticketSupport": MessageLookupByLibrary.simpleMessage("客服"),
    "ticketUnread": MessageLookupByLibrary.simpleMessage("有未读回复"),
    "ticketWaiting": MessageLookupByLibrary.simpleMessage("等待客服回复"),
    "ticketYou": MessageLookupByLibrary.simpleMessage("我"),
    "tight": MessageLookupByLibrary.simpleMessage("紧凑"),
    "time": MessageLookupByLibrary.simpleMessage("时间"),
    "timeout": MessageLookupByLibrary.simpleMessage("超时"),
    "timezoneLabel": MessageLookupByLibrary.simpleMessage("时区"),
    "tip": MessageLookupByLibrary.simpleMessage("提示"),
    "todayTraffic": MessageLookupByLibrary.simpleMessage("今日流量"),
    "toggle": MessageLookupByLibrary.simpleMessage("切换"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("调性点缀"),
    "toolbox": MessageLookupByLibrary.simpleMessage("工具箱"),
    "tools": MessageLookupByLibrary.simpleMessage("工具"),
    "totalCommission": MessageLookupByLibrary.simpleMessage("累计获得佣金"),
    "totalLoginCount": MessageLookupByLibrary.simpleMessage("登录次数"),
    "totalOrders": m68,
    "totalTrafficLabel": MessageLookupByLibrary.simpleMessage("总量"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy端口"),
    "trafficDetailRecords": MessageLookupByLibrary.simpleMessage("流量详细记录表"),
    "trafficDetails": MessageLookupByLibrary.simpleMessage("流量详情"),
    "trafficDetailsSubtitle": MessageLookupByLibrary.simpleMessage(
      "查看流量使用情况，掌握网络使用趋势",
    ),
    "trafficEmailReminder": MessageLookupByLibrary.simpleMessage("流量邮件提醒"),
    "trafficRate": MessageLookupByLibrary.simpleMessage("倍率"),
    "trafficRecordsFailed": MessageLookupByLibrary.simpleMessage("流量数据加载失败"),
    "trafficResetBilling": MessageLookupByLibrary.simpleMessage("重置"),
    "trafficResetUnavailable": MessageLookupByLibrary.simpleMessage(
      "当前套餐暂不支持流量重置",
    ),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("流量统计"),
    "tun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "tunActivationFailed": MessageLookupByLibrary.simpleMessage(
      "虚拟网卡未能启动，请导出日志查看检测和连接失败的原因。",
    ),
    "tunAdapterFailed": MessageLookupByLibrary.simpleMessage(
      "虚拟网卡或驱动初始化失败，请导出日志查看具体原因。",
    ),
    "tunAuthorizationCancelled": MessageLookupByLibrary.simpleMessage(
      "已取消管理员授权，未创建虚拟网卡。",
    ),
    "tunComponentMissing": MessageLookupByLibrary.simpleMessage(
      "服务组件或完整性校验文件缺失，请重新安装完整客户端。",
    ),
    "tunDesc": MessageLookupByLibrary.simpleMessage("仅在管理员模式生效"),
    "tunFailureHelp": MessageLookupByLibrary.simpleMessage(
      "虚拟网卡已关闭，失败详情已写入日志。可以重新授权重试；也可以选择系统代理，供支持系统代理的应用使用。",
    ),
    "tunHelperPortInUse": m69,
    "tunPermissionDenied": MessageLookupByLibrary.simpleMessage(
      "没有创建虚拟网卡所需的权限，请允许管理员授权。",
    ),
    "tunRepairService": MessageLookupByLibrary.simpleMessage("检测并修复服务"),
    "tunRestartComputerHelp": MessageLookupByLibrary.simpleMessage(
      "如重新授权并重试后仍无法开启，请尝试重启电脑后再开启虚拟网卡。重启后仍失败，请导出日志联系客服。",
    ),
    "tunRetry": MessageLookupByLibrary.simpleMessage("重新授权并重试"),
    "tunSecurityBlocked": MessageLookupByLibrary.simpleMessage(
      "Windows 安全策略阻止了辅助服务，请检查保护历史记录或联系管理员处理。",
    ),
    "tunServiceExited": MessageLookupByLibrary.simpleMessage(
      "辅助服务启动后异常退出，虚拟网卡未能就绪。",
    ),
    "tunServicePendingDelete": MessageLookupByLibrary.simpleMessage(
      "旧的辅助服务仍在等待 Windows 完成清理，暂时无法重新安装。",
    ),
    "tunServiceReady": MessageLookupByLibrary.simpleMessage(
      "辅助服务已就绪，请开启虚拟网卡验证连接。",
    ),
    "tunServiceTimeout": MessageLookupByLibrary.simpleMessage(
      "辅助服务停止或启动超时，未能完成虚拟网卡准备。",
    ),
    "tunServiceUnavailable": MessageLookupByLibrary.simpleMessage(
      "辅助服务未能就绪，可能被拦截或与当前安装版本不一致。",
    ),
    "tunStartFailed": MessageLookupByLibrary.simpleMessage("虚拟网卡启动失败"),
    "tunStarting": MessageLookupByLibrary.simpleMessage("虚拟网卡开启中"),
    "tunStartingDescription": MessageLookupByLibrary.simpleMessage(
      "正在检测辅助服务并启动虚拟网卡，请稍候。首次使用可能需要管理员授权。",
    ),
    "tunTools": MessageLookupByLibrary.simpleMessage("虚拟网卡工具"),
    "tunToolsDescription": MessageLookupByLibrary.simpleMessage(
      "首次启用需要管理员授权安装辅助服务。此工具会检查服务，并在缺失或版本不匹配时重新安装。服务就绪后仍需开启虚拟网卡，确认网卡创建成功。",
    ),
    "tunUseSystemProxy": MessageLookupByLibrary.simpleMessage("使用系统代理"),
    "tunWaiting": MessageLookupByLibrary.simpleMessage("已请求，等待连接及验证"),
    "turnOff": MessageLookupByLibrary.simpleMessage("关闭"),
    "turnOn": MessageLookupByLibrary.simpleMessage("开启"),
    "twoYearBilling": MessageLookupByLibrary.simpleMessage("两年付"),
    "unblockLoginIp": MessageLookupByLibrary.simpleMessage("解除"),
    "unblockLoginIpMessage": m70,
    "unblockLoginIpTitle": MessageLookupByLibrary.simpleMessage("解除这个 IP 的限制？"),
    "unbound": MessageLookupByLibrary.simpleMessage("未绑定"),
    "undo": MessageLookupByLibrary.simpleMessage("撤销"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("统一延迟"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage("去除握手等额外延迟"),
    "unknown": MessageLookupByLibrary.simpleMessage("未知"),
    "unknownClient": MessageLookupByLibrary.simpleMessage("未知客户端"),
    "unknownLocation": MessageLookupByLibrary.simpleMessage("未知地区"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage("未知网络错误"),
    "unlimitedTime": MessageLookupByLibrary.simpleMessage("不限时"),
    "unnamed": MessageLookupByLibrary.simpleMessage("未命名"),
    "unreachable": MessageLookupByLibrary.simpleMessage("无法连接"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "updateAll": MessageLookupByLibrary.simpleMessage("全部更新"),
    "upgradePlanAction": MessageLookupByLibrary.simpleMessage("升级套餐"),
    "upload": MessageLookupByLibrary.simpleMessage("上传"),
    "uploadSpeed": MessageLookupByLibrary.simpleMessage("上传速度"),
    "uploadTraffic": MessageLookupByLibrary.simpleMessage("上传流量"),
    "uploaded": MessageLookupByLibrary.simpleMessage("已上传"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("通过URL获取配置文件"),
    "urlTip": m71,
    "useHosts": MessageLookupByLibrary.simpleMessage("使用Hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("使用系统Hosts"),
    "usedTrafficLabel": MessageLookupByLibrary.simpleMessage("已使用"),
    "userAgent": MessageLookupByLibrary.simpleMessage("用户代理"),
    "userInfoFailed": MessageLookupByLibrary.simpleMessage("个人资料加载失败"),
    "userMapLabel": MessageLookupByLibrary.simpleMessage("用户"),
    "username": MessageLookupByLibrary.simpleMessage("用户名"),
    "validatingProxy": MessageLookupByLibrary.simpleMessage("正在验证代理网络…"),
    "validatingTargets": MessageLookupByLibrary.simpleMessage("正在验证目标域名与优选 IP"),
    "value": MessageLookupByLibrary.simpleMessage("值"),
    "verificationApiPending": MessageLookupByLibrary.simpleMessage("验证码接口待接入"),
    "verificationEmailSent": MessageLookupByLibrary.simpleMessage(
      "验证码已发送，如果未收到请检查垃圾邮箱",
    ),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("活力"),
    "view": MessageLookupByLibrary.simpleMessage("查看"),
    "viewApps": MessageLookupByLibrary.simpleMessage("查看应用"),
    "viewDetails": MessageLookupByLibrary.simpleMessage("查看详情"),
    "viewOrderDetails": MessageLookupByLibrary.simpleMessage("查看详情"),
    "viewSavedRules": MessageLookupByLibrary.simpleMessage("查看已保存规则"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "检测到VPN相关配置改动",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "通过VpnService自动路由系统所有流量",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage("重启VPN后改变生效"),
    "waitingForPayment": MessageLookupByLibrary.simpleMessage("等待支付结果"),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV配置"),
    "whatHappensAfterSwitch": MessageLookupByLibrary.simpleMessage("切换后会发生什么"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("白名单模式"),
    "withdrawalAccount": MessageLookupByLibrary.simpleMessage("收款账户"),
    "withdrawalAmount": MessageLookupByLibrary.simpleMessage("提现金额"),
    "withdrawalAmountExceeds": MessageLookupByLibrary.simpleMessage(
      "提现金额不能超过可用佣金",
    ),
    "withdrawalAmountInvalid": MessageLookupByLibrary.simpleMessage(
      "请输入有效的提现金额",
    ),
    "withdrawalMethod": MessageLookupByLibrary.simpleMessage("提现方式"),
    "withdrawalMethodAlipay": MessageLookupByLibrary.simpleMessage("支付宝"),
    "withdrawalMethodBank": MessageLookupByLibrary.simpleMessage("银行卡"),
    "withdrawalMethodUsdt": MessageLookupByLibrary.simpleMessage("USDT"),
    "withdrawalMethodWechat": MessageLookupByLibrary.simpleMessage("微信支付"),
    "withdrawalRequestTitle": MessageLookupByLibrary.simpleMessage("佣金提现申请"),
    "withdrawalTicketCreated": MessageLookupByLibrary.simpleMessage(
      "提现工单已提交，请等待管理员处理",
    ),
    "withdrawalTicketDescription": MessageLookupByLibrary.simpleMessage(
      "提交后将在系统内自动创建工单，管理员将根据工单内容处理。",
    ),
    "yearlyBilling": MessageLookupByLibrary.simpleMessage("年付"),
    "yearsAgo": m72,
    "zh_CN": MessageLookupByLibrary.simpleMessage("中文简体"),
    "zoomIn": MessageLookupByLibrary.simpleMessage("放大"),
    "zoomOut": MessageLookupByLibrary.simpleMessage("缩小"),
  };
}
