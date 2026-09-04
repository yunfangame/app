// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ja locale. All the
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
  String get localeName => 'ja';

  static String m0(current, total) => "${current} / ${total}";

  static String m1(index) => "API ノード ${index}";

  static String m2(reachable, total) =>
      "API エンドポイント ${reachable}/${total} 件が利用可能";

  static String m3(count) => "全 ${count} の国と地域";

  static String m4(count) => "${count}日前";

  static String m5(label) => "選択された${label}を削除してもよろしいですか？";

  static String m6(label) => "現在の${label}を削除してもよろしいですか？";

  static String m7(label) => "${label}詳細";

  static String m8(label) => "${label}は空欄にできません";

  static String m9(count) => "${count} エントリ";

  static String m10(label) => "現在の${label}は既に存在しています";

  static String m11(name) => "${name} はすでに最新です";

  static String m12(name) => "${name} 更新済み";

  static String m13(name) => "${name}を更新中...";

  static String m14(count) => "${count}時間前";

  static String m15(count) => "${count} 時間";

  static String m16(target) => "${target} は無効なポリシーです";

  static String m17(proxyName) => "${proxyName} は無効なプロキシです";

  static String m18(providerName) => "${providerName} は無効なプロキシプロバイダーです";

  static String m19(subRule) => "${subRule} は無効なSUB_RULEです";

  static String m20(count) => "${count} 件の接続";

  static String m21(appName) =>
      "1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check ${appName} in the right list\n\nAfter completing the setup, return to the app and use it normally. Thank you for your cooperation.";

  static String m22(index) => "接続先${index}";

  static String m23(count) => "${count}分前";

  static String m24(count) => "${count}ヶ月前";

  static String m25(reachable, total) => "${reachable}/${total} を解決可能";

  static String m26(address) => "${address} は待受中です";

  static String m27(address) => "${address} に接続できません";

  static String m28(code, stage, error) => "${code} / ${stage}${error}";

  static String m29(address) => "${address} を読み戻して確認しました";

  static String m30(date) => "次回のプランリセット：${date}";

  static String m31(count) => "全 ${count} ノード";

  static String m32(label) => "まだ${label}はありません";

  static String m33(label) => "${label}は数字でなければなりません";

  static String m34(current, total) => "${current} / ${total} ページ";

  static String m35(count) => "${count}人";

  static String m36(label) => "${label} は 1024 から 49151 の間でなければなりません";

  static String m37(count) => "${count} 件保存済み。上書き有効時に適用されます";

  static String m38(count) => "${count} 秒";

  static String m39(count) => "${count} 項目が選択されています";

  static String m40(date) => "プランは ${date} に期限切れとなりました。更新後に引き続きご利用いただけます。";

  static String m41(date) => "プランは ${date} に期限切れとなり、残り 3 日未満です。早めに更新してください。";

  static String m42(remaining) =>
      "残り通信量は ${remaining} GB で、10 GB を下回っています。早めに購入または更新してください。";

  static String m43(code) =>
      "システムプロキシを有効にできませんでした（${code}）。スイッチを元に戻しました。診断用ログをエクスポートしてください";

  static String m44(code) =>
      "システムプロキシを無効にできませんでした（${code}）。Windows の設定で手動で無効にしてください";

  static String m45(count) => "全 ${count} 件";

  static String m46(label) => "${label}はURLである必要があります";

  static String m47(count) => "${count}年前";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("について"),
    "acceleratorHome": MessageLookupByLibrary.simpleMessage("アクセラレーター"),
    "accessControl": MessageLookupByLibrary.simpleMessage("アクセス制御"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "選択したアプリのみVPNを許可",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "アプリケーションのプロキシアクセスを設定",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "選択したアプリをVPNから除外",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage("アクセス制御設定"),
    "accessTime": MessageLookupByLibrary.simpleMessage("接続時間"),
    "account": MessageLookupByLibrary.simpleMessage("アカウント"),
    "accountBalance": MessageLookupByLibrary.simpleMessage("アカウント残高"),
    "accountCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "アカウント情報とセキュリティ設定を管理します",
    ),
    "action": MessageLookupByLibrary.simpleMessage("アクション"),
    "action_mode": MessageLookupByLibrary.simpleMessage("モード切替"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "action_start": MessageLookupByLibrary.simpleMessage("開始/停止"),
    "action_tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "action_view": MessageLookupByLibrary.simpleMessage("表示/非表示"),
    "actions": MessageLookupByLibrary.simpleMessage("操作"),
    "activateNow": MessageLookupByLibrary.simpleMessage("今すぐ有効化"),
    "actualConnectionDelay": MessageLookupByLibrary.simpleMessage("実測遅延"),
    "add": MessageLookupByLibrary.simpleMessage("追加"),
    "addProfile": MessageLookupByLibrary.simpleMessage("プロファイルを追加"),
    "addProxies": MessageLookupByLibrary.simpleMessage("プロキシを追加"),
    "addProxy": MessageLookupByLibrary.simpleMessage("プロキシを追加"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループを追加"),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage("プロキシプロバイダーを追加"),
    "addRule": MessageLookupByLibrary.simpleMessage("ルールを追加"),
    "addSsid": MessageLookupByLibrary.simpleMessage("SSIDを追加"),
    "addedRules": MessageLookupByLibrary.simpleMessage("追加ルール"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage("追加パラメータ"),
    "address": MessageLookupByLibrary.simpleMessage("アドレス"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAVサーバーアドレス"),
    "addressTip": MessageLookupByLibrary.simpleMessage("有効なWebDAVアドレスを入力"),
    "advancedConfig": MessageLookupByLibrary.simpleMessage("高度な設定"),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage("多様な設定を提供"),
    "advancedSettings": MessageLookupByLibrary.simpleMessage("詳細設定"),
    "advancedSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "VPN の動作とネットワーク設定をカスタマイズします",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("同意"),
    "allGeodataUpdated": MessageLookupByLibrary.simpleMessage(
      "すべての地理データを更新しました",
    ),
    "allPlans": MessageLookupByLibrary.simpleMessage("すべて"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("アプリがVPNをバイパスすることを許可"),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "有効化すると一部アプリがVPNをバイパス",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("LANを許可"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage("LAN経由でのプロキシアクセスを許可"),
    "alreadyHaveAccount": MessageLookupByLibrary.simpleMessage(
      "すでにアカウントをお持ちですか？",
    ),
    "announcementCenter": MessageLookupByLibrary.simpleMessage("お知らせセンター"),
    "announcementPosition": m0,
    "announcementTooltip": MessageLookupByLibrary.simpleMessage("お知らせを表示"),
    "announcementUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "オフラインモードでは最新のお知らせを取得できません",
    ),
    "apiEndpointApplied": MessageLookupByLibrary.simpleMessage(
      "グローバル優先 API 接続先に設定しました",
    ),
    "apiEndpointLabel": m1,
    "apiEndpointsAvailable": m2,
    "apiStatus": MessageLookupByLibrary.simpleMessage("API 接続状態"),
    "apiStatusUnavailable": MessageLookupByLibrary.simpleMessage(
      "API 接続状態を取得できません",
    ),
    "app": MessageLookupByLibrary.simpleMessage("アプリ"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("アプリアクセス制御"),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage("システムDNSを追加"),
    "appendSystemDnsTip": MessageLookupByLibrary.simpleMessage(
      "設定にシステムDNSを強制的に追加します",
    ),
    "application": MessageLookupByLibrary.simpleMessage("アプリケーション"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage("アプリ関連設定を変更"),
    "applyPreferredIps": MessageLookupByLibrary.simpleMessage("すべて適用"),
    "asnLabel": MessageLookupByLibrary.simpleMessage("ASN"),
    "authorized": MessageLookupByLibrary.simpleMessage("許可済み"),
    "auto": MessageLookupByLibrary.simpleMessage("自動"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage("自動更新チェック"),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "起動時に更新を自動チェック",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("接続を自動閉じる"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "ノード変更後に接続を自動閉じる",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("自動起動"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage("システムの自動起動に従う"),
    "autoRefresh": MessageLookupByLibrary.simpleMessage("自動更新"),
    "autoRenew": MessageLookupByLibrary.simpleMessage("自動更新"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自動実行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("アプリ起動時に自動実行"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("オートセットシステムDNS"),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自動更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自動更新間隔（分）"),
    "automaticLogin": MessageLookupByLibrary.simpleMessage("自動ログイン"),
    "automaticLoginUnavailable": MessageLookupByLibrary.simpleMessage(
      "自動ログインを利用できません。手動でログインするか、後でもう一度お試しください",
    ),
    "automaticSelection": MessageLookupByLibrary.simpleMessage("自動選択"),
    "availabilityRate": MessageLookupByLibrary.simpleMessage("稼働率"),
    "availableCommissionEmpty": MessageLookupByLibrary.simpleMessage(
      "移行できる報酬がありません",
    ),
    "availableCount": MessageLookupByLibrary.simpleMessage("利用可能"),
    "availableEndpoints": MessageLookupByLibrary.simpleMessage("利用可能な接続先"),
    "backToLogin": MessageLookupByLibrary.simpleMessage("ログインに戻る"),
    "backup": MessageLookupByLibrary.simpleMessage("バックアップ"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage("バックアップと復元"),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVまたはファイルを介してデータを同期する",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("バックアップ成功"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("基本設定"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage("基本設定をグローバルに変更"),
    "basicInfo": MessageLookupByLibrary.simpleMessage("基本情報"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("基本戦略"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "To ensure background operation, please disable battery optimization for this app. Tap to go to settings.",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "システムの影響により、この状態は必ずしも正確とは限りません。",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("バインド"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("ブラックリストモード"),
    "bound": MessageLookupByLibrary.simpleMessage("連携済み"),
    "brandName": MessageLookupByLibrary.simpleMessage("FengWo Accelerator"),
    "buyNow": MessageLookupByLibrary.simpleMessage("今すぐ購入"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("バイパスドメイン"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage("システムプロキシ有効時のみ適用"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "キャッシュが破損しています。クリアしますか？",
    ),
    "campusNetworkApplyFailed": MessageLookupByLibrary.simpleMessage(
      "キャンパスネットワークモードを適用できませんでした。接続を確認して再試行してください",
    ),
    "campusNetworkDisabled": MessageLookupByLibrary.simpleMessage(
      "キャンパスネットワークモードを無効にしました",
    ),
    "campusNetworkEnabled": MessageLookupByLibrary.simpleMessage(
      "キャンパスネットワークモードを有効にしました",
    ),
    "campusNetworkInformation": MessageLookupByLibrary.simpleMessage(
      "無効時は CDN の通常の名前解決を使用します。有効化または回線変更後にコア設定を自動で再読み込みします。",
    ),
    "campusNetworkLine": MessageLookupByLibrary.simpleMessage("入口回線"),
    "campusNetworkLine1": MessageLookupByLibrary.simpleMessage("回線1"),
    "campusNetworkLine2": MessageLookupByLibrary.simpleMessage("回線2"),
    "campusNetworkLine3": MessageLookupByLibrary.simpleMessage("回線3"),
    "campusNetworkMode": MessageLookupByLibrary.simpleMessage("キャンパスネットワークモード"),
    "campusNetworkModeSubtitle": MessageLookupByLibrary.simpleMessage(
      "キャンパスネットワーク用の専用入口回線に切り替えます",
    ),
    "campusNetworkSwitch": MessageLookupByLibrary.simpleMessage(
      "キャンパスネットワークモードを有効にする",
    ),
    "campusNetworkSwitchDescription": MessageLookupByLibrary.simpleMessage(
      "有効にするとノードドメインを選択した入口回線に割り当てます",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("キャンセル"),
    "cancelOrder": MessageLookupByLibrary.simpleMessage("注文をキャンセル"),
    "cancelOrderMessage": MessageLookupByLibrary.simpleMessage(
      "キャンセル後は支払いできません。必要な場合は新しく注文してください。",
    ),
    "cancelOrderTitle": MessageLookupByLibrary.simpleMessage("この注文をキャンセルしますか？"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("全選択解除"),
    "candidateCount": MessageLookupByLibrary.simpleMessage("候補"),
    "carrier": MessageLookupByLibrary.simpleMessage("通信事業者"),
    "cfApplyFailed": MessageLookupByLibrary.simpleMessage(
      "CF 最適 IP を適用できなかったため、元の設定に戻しました",
    ),
    "cfApplySuccess": MessageLookupByLibrary.simpleMessage(
      "CF 最適 IP を適用し、コア設定を再読み込みしました",
    ),
    "cfTargetMissingMessage": MessageLookupByLibrary.simpleMessage(
      "CF 最適化で置き換えるノードのドメインをリモート設定に追加してください。",
    ),
    "cfTargetMissingTitle": MessageLookupByLibrary.simpleMessage(
      "対象ドメインが未設定です",
    ),
    "cfTargetValidationFailed": MessageLookupByLibrary.simpleMessage(
      "対象ドメインの TLS 検証に失敗したため、設定は変更されませんでした",
    ),
    "chainProxy": MessageLookupByLibrary.simpleMessage("チェーンプロキシ"),
    "chainProxyActive": MessageLookupByLibrary.simpleMessage("チェーンプロキシは実行中です"),
    "chainProxyApplyFailed": MessageLookupByLibrary.simpleMessage(
      "コア設定の適用に失敗し、元の設定に戻しました",
    ),
    "chainProxyConnectivityFailed": MessageLookupByLibrary.simpleMessage(
      "チェーンプロキシの接続確認に失敗したため、無効化して元の設定に戻しました",
    ),
    "chainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "追加の SOCKS5 または HTTP 出口を管理します",
    ),
    "chainProxyDirectModeUnsupported": MessageLookupByLibrary.simpleMessage(
      "送出モードをルールまたはグローバルに変更してください",
    ),
    "chainProxyDisabled": MessageLookupByLibrary.simpleMessage("チェーンプロキシは無効です"),
    "chainProxyEnabled": MessageLookupByLibrary.simpleMessage(
      "チェーンプロキシを開始しました",
    ),
    "chainProxyLocked": MessageLookupByLibrary.simpleMessage(
      "実行中は他の設定を操作できません",
    ),
    "chainProxyRollbackFailed": MessageLookupByLibrary.simpleMessage(
      "チェーンプロキシの適用に失敗し、元の設定も復元できませんでした。アプリを再起動してください",
    ),
    "chainProxySessionNotice": MessageLookupByLibrary.simpleMessage(
      "有効にすると、プロキシ通信は現在のノードを経由してからチェーンプロキシで送出されます。",
    ),
    "chainProxyStopped": MessageLookupByLibrary.simpleMessage(
      "チェーンプロキシを停止しました",
    ),
    "changePasswordTitle": MessageLookupByLibrary.simpleMessage("パスワード変更"),
    "changePlanAction": MessageLookupByLibrary.simpleMessage("プランを変更"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("更新を確認"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("アプリは最新版です"),
    "checkingApiStatus": MessageLookupByLibrary.simpleMessage(
      "API 接続を確認しています...",
    ),
    "checkingLoginStatus": MessageLookupByLibrary.simpleMessage(
      "ログイン状態を確認しています...",
    ),
    "chooseSpeedTest": MessageLookupByLibrary.simpleMessage("測定先を選択"),
    "clearData": MessageLookupByLibrary.simpleMessage("データを消去"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("クリップボードにエクスポート"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("クリップボードからインポート"),
    "closeAction": MessageLookupByLibrary.simpleMessage("閉じる"),
    "closeAllConnections": MessageLookupByLibrary.simpleMessage("すべての接続を切断"),
    "closeAllConnectionsDescription": MessageLookupByLibrary.simpleMessage(
      "現在の接続をすべて切断します。アプリが自動的に再接続する場合があります。",
    ),
    "closeConnection": MessageLookupByLibrary.simpleMessage("接続を切断"),
    "cloudflarePreferredIp": MessageLookupByLibrary.simpleMessage("CF 最適 IP"),
    "cloudflarePreferredIpDescription": MessageLookupByLibrary.simpleMessage(
      "現在の回線に適した Cloudflare エッジを検索します",
    ),
    "color": MessageLookupByLibrary.simpleMessage("カラー"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("カラースキーム"),
    "columns": MessageLookupByLibrary.simpleMessage("列"),
    "commission": MessageLookupByLibrary.simpleMessage("報酬"),
    "commissionPayoutRecords": MessageLookupByLibrary.simpleMessage("報酬支給履歴"),
    "commissionRate": MessageLookupByLibrary.simpleMessage("報酬率"),
    "commissionTransfer": MessageLookupByLibrary.simpleMessage("残高へ移行"),
    "commissionTransferConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "報酬はプラン購入に使えるアカウント残高へ移行されます。",
    ),
    "commissionTransferConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "利用可能な報酬をすべて移行しますか？",
    ),
    "commissionTransferred": MessageLookupByLibrary.simpleMessage(
      "報酬をアカウント残高へ移行しました",
    ),
    "commissionWithdraw": MessageLookupByLibrary.simpleMessage("報酬を出金"),
    "compatible": MessageLookupByLibrary.simpleMessage("互換モード"),
    "completedCount": MessageLookupByLibrary.simpleMessage("完了"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "設定内にデータが検出されました",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("確認"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "すべてのデータをクリアしてもよろしいですか？",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "現在のプロキシグループを削除してもよろしいですか？",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "現在のウィンドウを閉じてもよろしいですか？",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "コアを強制的にクラッシュさせてもよろしいですか？",
    ),
    "confirmNewPassword": MessageLookupByLibrary.simpleMessage("新しいパスワードを確認"),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "確認後、既存のデータは上書きされます",
    ),
    "confirmPassword": MessageLookupByLibrary.simpleMessage("パスワード確認"),
    "confirmReset": MessageLookupByLibrary.simpleMessage("リセットする"),
    "connected": MessageLookupByLibrary.simpleMessage("接続済み"),
    "connecting": MessageLookupByLibrary.simpleMessage("接続中..."),
    "connection": MessageLookupByLibrary.simpleMessage("接続"),
    "connectionDetails": MessageLookupByLibrary.simpleMessage("接続の詳細"),
    "connectionRuleAlreadyExists": MessageLookupByLibrary.simpleMessage(
      "このルールは既に存在します。設定を再適用しました",
    ),
    "connectionRuleApplied": MessageLookupByLibrary.simpleMessage(
      "ルールを追加して適用しました",
    ),
    "connectionRuleAppliedAndSwitched": MessageLookupByLibrary.simpleMessage(
      "ルールを追加し、ルールモードに切り替えました",
    ),
    "connectionStatus": MessageLookupByLibrary.simpleMessage("接続状態"),
    "connections": MessageLookupByLibrary.simpleMessage("接続"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage("現在の接続データを表示"),
    "connectivity": MessageLookupByLibrary.simpleMessage("接続性："),
    "consumptionOnly": MessageLookupByLibrary.simpleMessage("支払い専用"),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage("内容は空にできません"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("コンテンツテーマ"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "グローバル追加ルールを制御",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("コピー"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("環境変数をコピー"),
    "copyInviteCode": MessageLookupByLibrary.simpleMessage("招待コードをコピー"),
    "copyLink": MessageLookupByLibrary.simpleMessage("リンクをコピー"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("コピー成功"),
    "core": MessageLookupByLibrary.simpleMessage("コア"),
    "coreIpv6": MessageLookupByLibrary.simpleMessage("コア IPv6"),
    "coreIpv6Description": MessageLookupByLibrary.simpleMessage(
      "Mihomo のトップレベル IPv6 機能を制御します",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("コアステータス"),
    "countriesAndRegions": MessageLookupByLibrary.simpleMessage("国と地域"),
    "countriesCount": m3,
    "country": MessageLookupByLibrary.simpleMessage("国"),
    "countryRegion": MessageLookupByLibrary.simpleMessage("国/地域"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("クラッシュを検出しました"),
    "crashDetectedTip": MessageLookupByLibrary.simpleMessage(
      "前回の実行中にアプリがクラッシュしました。クラッシュの繰り返しを防ぐため、現在のプロファイルを解除し、設定の自動セットアップをスキップしました。",
    ),
    "crashTest": MessageLookupByLibrary.simpleMessage("クラッシュテスト"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("クラッシュ分析"),
    "crashlyticsTip": MessageLookupByLibrary.simpleMessage(
      "有効にすると、アプリがクラッシュした際に機密情報を含まないクラッシュログを自動的にアップロードします",
    ),
    "create": MessageLookupByLibrary.simpleMessage("作成"),
    "createAccountSubtitle": MessageLookupByLibrary.simpleMessage(
      "参加してネットワーク管理を始めましょう",
    ),
    "createAccountTitle": MessageLookupByLibrary.simpleMessage("アカウント作成"),
    "createProfile": MessageLookupByLibrary.simpleMessage("Create Profile"),
    "createdAt": MessageLookupByLibrary.simpleMessage("作成日時"),
    "creatingOrder": MessageLookupByLibrary.simpleMessage("注文を作成しています…"),
    "creationTime": MessageLookupByLibrary.simpleMessage("作成時間"),
    "currentActiveConnections": MessageLookupByLibrary.simpleMessage("現在の接続数"),
    "currentEndpoint": MessageLookupByLibrary.simpleMessage("現在使用中"),
    "currentMonthTraffic": MessageLookupByLibrary.simpleMessage("今月の通信量"),
    "currentNode": MessageLookupByLibrary.simpleMessage("現在のノード"),
    "currentNodeDelay": MessageLookupByLibrary.simpleMessage("現在のノード遅延"),
    "currentPlanLabel": MessageLookupByLibrary.simpleMessage("現在のプラン"),
    "custom": MessageLookupByLibrary.simpleMessage("カスタム"),
    "customDnsServers": MessageLookupByLibrary.simpleMessage("カスタム DNS サーバー"),
    "cut": MessageLookupByLibrary.simpleMessage("切り取り"),
    "dailyBrowsingRuleMode": MessageLookupByLibrary.simpleMessage(
      "通常の閲覧：ルールモードの方が安定します。",
    ),
    "dark": MessageLookupByLibrary.simpleMessage("ダーク"),
    "dashboard": MessageLookupByLibrary.simpleMessage("ダッシュボード"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "データの変更が検出されました。保存しますか？",
    ),
    "dataCollectionContent": MessageLookupByLibrary.simpleMessage(
      "本アプリはFirebase Crashlyticsを使用してクラッシュ情報を収集し、アプリの安定性を向上させます。\n収集されるデータにはデバイス情報とクラッシュ詳細が含まれますが、個人の機密データは含まれません。\n設定でこの機能を無効にすることができます。",
    ),
    "dataCollectionTip": MessageLookupByLibrary.simpleMessage("データ収集説明"),
    "dataSource": MessageLookupByLibrary.simpleMessage("データソース"),
    "dateLabel": MessageLookupByLibrary.simpleMessage("日付"),
    "daysAgo": m4,
    "defaultNameserver": MessageLookupByLibrary.simpleMessage("デフォルトネームサーバー"),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "DNSサーバーの解決用",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("デフォルト"),
    "delay": MessageLookupByLibrary.simpleMessage("遅延"),
    "delayTest": MessageLookupByLibrary.simpleMessage("遅延テスト"),
    "delete": MessageLookupByLibrary.simpleMessage("削除"),
    "deleteMultipTip": m5,
    "deleteTip": m6,
    "desc": MessageLookupByLibrary.simpleMessage(
      "ClashMetaベースのマルチプラットフォームプロキシクライアント。シンプルで使いやすく、オープンソースで広告なし。",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("宛先"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage("宛先地理情報"),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage("宛先IP ASN"),
    "details": m7,
    "detectionTip": MessageLookupByLibrary.simpleMessage("サードパーティAPIに依存（参考値）"),
    "developerMode": MessageLookupByLibrary.simpleMessage("デベロッパーモード"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "デベロッパーモードが有効になりました。",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("ダイレクト"),
    "disableProxy": MessageLookupByLibrary.simpleMessage("停止"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("UDPを無効化"),
    "disclaimer": MessageLookupByLibrary.simpleMessage("免責事項"),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "本ソフトウェアは学習交流や科学研究などの非営利目的でのみ使用されます。商用利用は厳禁です。いかなる商用活動も本ソフトウェアとは無関係です。",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("切断済み"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage("新バージョンを発見"),
    "dnsDesc": MessageLookupByLibrary.simpleMessage("DNS関連設定の更新"),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNSハイジャッキング"),
    "dnsIpv6": MessageLookupByLibrary.simpleMessage("DNS IPv6"),
    "dnsIpv6Description": MessageLookupByLibrary.simpleMessage(
      "DNS クエリで IPv6 レコードを返します",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNSモード"),
    "dnsOverrideInformation": MessageLookupByLibrary.simpleMessage(
      "有効にすると、プロファイルの DNS 設定ではなくアプリ内蔵の DNS 設定を使用します",
    ),
    "dnsSettings": MessageLookupByLibrary.simpleMessage("DNS 設定"),
    "dnsSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "DNS 解決設定を管理します",
    ),
    "doNotRemindToday": MessageLookupByLibrary.simpleMessage("今日は再度表示しない"),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage("通過させますか？"),
    "domain": MessageLookupByLibrary.simpleMessage("ドメイン"),
    "domainOrService": MessageLookupByLibrary.simpleMessage("ドメイン / サービス"),
    "done": MessageLookupByLibrary.simpleMessage("完了"),
    "dontShowAgain": MessageLookupByLibrary.simpleMessage("今後表示しない"),
    "download": MessageLookupByLibrary.simpleMessage("ダウンロード"),
    "downloadSpeed": MessageLookupByLibrary.simpleMessage("ダウンロード速度"),
    "downloadTraffic": MessageLookupByLibrary.simpleMessage("ダウンロード"),
    "downloaded": MessageLookupByLibrary.simpleMessage("ダウンロード済み"),
    "edit": MessageLookupByLibrary.simpleMessage("編集"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage("グローバルルールを編集"),
    "editProxy": MessageLookupByLibrary.simpleMessage("プロキシを編集"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループを編集"),
    "editRule": MessageLookupByLibrary.simpleMessage("ルールを編集"),
    "editSsid": MessageLookupByLibrary.simpleMessage("SSIDを編集"),
    "email": MessageLookupByLibrary.simpleMessage("メールアドレス"),
    "emailVerificationCode": MessageLookupByLibrary.simpleMessage("メール認証コード"),
    "emptyTip": m8,
    "en": MessageLookupByLibrary.simpleMessage("英語"),
    "enableOfflineAction": MessageLookupByLibrary.simpleMessage("オフラインモードを有効化"),
    "enableOfflineDescription": MessageLookupByLibrary.simpleMessage(
      "オンラインログイン確認とアカウント更新を省略し、キャッシュ済みのサブスクリプション、ノード、アカウント概要を使用します。",
    ),
    "enableOfflineTitle": MessageLookupByLibrary.simpleMessage(
      "オフラインモードを有効にしますか？",
    ),
    "enableProxy": MessageLookupByLibrary.simpleMessage("有効にする"),
    "enterConfirmPassword": MessageLookupByLibrary.simpleMessage(
      "パスワードをもう一度入力してください",
    ),
    "enterEmail": MessageLookupByLibrary.simpleMessage("メールアドレスを入力してください"),
    "enterEmailAddress": MessageLookupByLibrary.simpleMessage(
      "メールアドレスを入力してください",
    ),
    "enterInvitationCode": MessageLookupByLibrary.simpleMessage(
      "招待コードを入力（お持ちの場合）",
    ),
    "enterNewPassword": MessageLookupByLibrary.simpleMessage(
      "新しいパスワードを入力してください",
    ),
    "enterOldPassword": MessageLookupByLibrary.simpleMessage(
      "現在のパスワードを入力してください",
    ),
    "enterPassword": MessageLookupByLibrary.simpleMessage("パスワードを入力してください"),
    "enterVerificationCode": MessageLookupByLibrary.simpleMessage("認証コードを入力"),
    "enterWithdrawalAccount": MessageLookupByLibrary.simpleMessage(
      "受取口座またはアドレスを入力してください",
    ),
    "enterWithdrawalAmount": MessageLookupByLibrary.simpleMessage(
      "出金金額を入力してください",
    ),
    "entries": MessageLookupByLibrary.simpleMessage(" エントリ"),
    "entriesCount": m9,
    "exclude": MessageLookupByLibrary.simpleMessage("最近のタスクから非表示"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "アプリがバックグラウンド時に最近のタスクから非表示",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage("除外プロキシフィルター"),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Exclude SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "When connected to an excluded SSID Wi-Fi, the app running state will be automatically switched.",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("除外タイプ"),
    "existsTip": m10,
    "exit": MessageLookupByLibrary.simpleMessage("終了"),
    "expand": MessageLookupByLibrary.simpleMessage("標準"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("期待されるステータス"),
    "expiryEmailReminder": MessageLookupByLibrary.simpleMessage("期限切れメール通知"),
    "exportFile": MessageLookupByLibrary.simpleMessage("ファイルをエクスポート"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("ログをエクスポート"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("エクスポート成功"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("エクスプレッシブ"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部コントローラー"),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとClashコアをポート9090で制御可能",
    ),
    "externalFetch": MessageLookupByLibrary.simpleMessage("外部取得"),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部リンク"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fakeipフィルター"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fakeip範囲"),
    "fallback": MessageLookupByLibrary.simpleMessage("フォールバック"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage("通常はオフショアDNSを使用"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("フォールバックフィルター"),
    "fastestDownload": MessageLookupByLibrary.simpleMessage("最高速度"),
    "featureComingSoon": MessageLookupByLibrary.simpleMessage(
      "この機能はサーバー接続後に利用できます",
    ),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("ハイファイデリティー"),
    "file": MessageLookupByLibrary.simpleMessage("ファイル"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("プロファイルを直接アップロード"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "ファイルが変更されました。保存しますか？",
    ),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("プロセス検出"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとパフォーマンスが若干低下します",
    ),
    "fontFamily": MessageLookupByLibrary.simpleMessage("フォントファミリー"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "コアを強制再起動してもよろしいですか？",
    ),
    "forgotPassword": MessageLookupByLibrary.simpleMessage("パスワードを忘れた場合"),
    "forgotPasswordSubtitle": MessageLookupByLibrary.simpleMessage(
      "パスワードを再設定してアカウントへのアクセスを復元します",
    ),
    "forgotPasswordTitle": MessageLookupByLibrary.simpleMessage("パスワードの再設定"),
    "freeLabel": MessageLookupByLibrary.simpleMessage("無料"),
    "freeOrder": MessageLookupByLibrary.simpleMessage("無料で有効化"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("フルーツサラダ"),
    "general": MessageLookupByLibrary.simpleMessage("一般"),
    "generateInviteCode": MessageLookupByLibrary.simpleMessage("招待コードを作成"),
    "generateMihomoRule": MessageLookupByLibrary.simpleMessage(
      "現在の接続から Mihomo ルールを生成",
    ),
    "generatePaymentQr": MessageLookupByLibrary.simpleMessage("決済QRコードを生成"),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("自動更新"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage("自動更新間隔"),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "自動更新間隔は0より大きくなければなりません",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geoオプション"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geoリソース"),
    "geoSkipped": m11,
    "geoUpdated": m12,
    "geoUpdating": m13,
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低メモリモード"),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとGeo低メモリローダーを使用",
    ),
    "geodataSettings": MessageLookupByLibrary.simpleMessage("地理データ"),
    "geodataSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "GeoIP と GeoSite データベースを更新します",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("GeoIPコード"),
    "global": MessageLookupByLibrary.simpleMessage("グローバル"),
    "globalAccelerationNetwork": MessageLookupByLibrary.simpleMessage(
      "グローバル高速ネットワーク",
    ),
    "globalModeWarningDescription": MessageLookupByLibrary.simpleMessage(
      "グローバルモードはすべてのネットワーク通信を処理します。初回は DIRECT を使用し、確認後にプロキシノードを選択できます。",
    ),
    "globalNodeDistribution": MessageLookupByLibrary.simpleMessage(
      "グローバルノード分布",
    ),
    "globalRuleModeSwitchHint": MessageLookupByLibrary.simpleMessage(
      "現在はグローバルモードです。追加後はルールモードへ切り替え、この接続には上のポリシーを、その他の通信には選択したプロキシグループを使用します。",
    ),
    "go": MessageLookupByLibrary.simpleMessage("移動"),
    "goDownload": MessageLookupByLibrary.simpleMessage("ダウンロードへ"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage("スクリプト設定に移動"),
    "halfYearBilling": MessageLookupByLibrary.simpleMessage("6か月"),
    "handlingFee": MessageLookupByLibrary.simpleMessage("手数料"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("変更をキャッシュしますか？"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper サービスが利用できないため、TUN モードを有効にできません。再インストールしてください。",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("リストから隠す"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("パスワードを隠す"),
    "highestLatency": MessageLookupByLibrary.simpleMessage("最大遅延"),
    "host": MessageLookupByLibrary.simpleMessage("ホスト"),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("ホストを追加"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("ホットキー競合"),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("ホットキー管理"),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "キーボードでアプリを制御",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("時間"),
    "hoursAgo": m14,
    "hoursCount": m15,
    "iHavePaid": MessageLookupByLibrary.simpleMessage("支払い済み、状態を更新"),
    "icon": MessageLookupByLibrary.simpleMessage("アイコン"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("アイコン履歴"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("アイコンスタイル"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("アイコンURL"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Ignore Battery Optimization",
    ),
    "import": MessageLookupByLibrary.simpleMessage("インポート"),
    "importFile": MessageLookupByLibrary.simpleMessage("ファイルからインポート"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("URLからインポート"),
    "importUrl": MessageLookupByLibrary.simpleMessage("URLからインポート"),
    "inAppPayment": MessageLookupByLibrary.simpleMessage("アプリ内決済"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage("すべてのプロキシを含める"),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "プロキシグループに含まれないすべてのプロキシをインポートします。下でさらにプロキシグループを追加できます",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "すべてのプロキシプロバイダーを含める",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "有効にすると、インポートされたプロキシプロバイダーを上書きします",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("長期有効"),
    "init": MessageLookupByLibrary.simpleMessage("初期化"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage("正しいホットキーを入力"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage("プロキシグループ名を入力"),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage("ルール内容を入力"),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("インテリジェント選択"),
    "internet": MessageLookupByLibrary.simpleMessage("インターネット"),
    "interval": MessageLookupByLibrary.simpleMessage("インターバル"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("イントラネットIP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage("無効なバックアップファイル"),
    "invalidEmail": MessageLookupByLibrary.simpleMessage("有効なメールアドレスを入力してください"),
    "invalidEmailAccount": MessageLookupByLibrary.simpleMessage(
      "有効なメールアカウントを入力してください",
    ),
    "invalidPolicy": m16,
    "invalidPort": MessageLookupByLibrary.simpleMessage("有効なポートを入力してください"),
    "invalidProxy": m17,
    "invalidProxyProvider": m18,
    "invalidSubRule": m19,
    "invitationCode": MessageLookupByLibrary.simpleMessage("招待コード"),
    "invitationCodeOptional": MessageLookupByLibrary.simpleMessage("招待コード（任意）"),
    "invitationCodeRequired": MessageLookupByLibrary.simpleMessage(
      "招待コードを入力してください",
    ),
    "inviteCode": MessageLookupByLibrary.simpleMessage("招待コード"),
    "inviteCodeCopied": MessageLookupByLibrary.simpleMessage("招待コードをコピーしました"),
    "inviteCodeDescription": MessageLookupByLibrary.simpleMessage(
      "専用コードを共有し、友達が登録してプランを購入すると報酬を獲得できます。",
    ),
    "inviteCodeGenerated": MessageLookupByLibrary.simpleMessage("招待コードを作成しました"),
    "inviteCodeManagement": MessageLookupByLibrary.simpleMessage("招待コード管理"),
    "inviteHeroSubtitle": MessageLookupByLibrary.simpleMessage(
      "招待するほど報酬アップ。上限はありません！",
    ),
    "inviteHeroTitle": MessageLookupByLibrary.simpleMessage("友達を招待して報酬を獲得"),
    "inviteLoadFailed": MessageLookupByLibrary.simpleMessage(
      "招待データを読み込めませんでした",
    ),
    "invitePromotion": MessageLookupByLibrary.simpleMessage("招待特典"),
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP アドレス"),
    "ipLookup": MessageLookupByLibrary.simpleMessage("IP 検索"),
    "ipLookupDescription": MessageLookupByLibrary.simpleMessage(
      "公開 IP の地域や通信事業者などを確認します",
    ),
    "ipLookupFailed": MessageLookupByLibrary.simpleMessage(
      "IP 情報を取得できません。接続を確認して再試行してください",
    ),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IPCIDR"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage("有効化するとIPv6トラフィックを受信可能"),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage("IPv6インバウンドを許可"),
    "ipv6Settings": MessageLookupByLibrary.simpleMessage("IPv6 設定"),
    "ipv6SettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Mihomo の IPv6 接続機能を管理します",
    ),
    "ja": MessageLookupByLibrary.simpleMessage("日本語"),
    "justNow": MessageLookupByLibrary.simpleMessage("たった今"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "TCPキープアライブ間隔",
    ),
    "keptCount": MessageLookupByLibrary.simpleMessage("採用"),
    "key": MessageLookupByLibrary.simpleMessage("キー"),
    "language": MessageLookupByLibrary.simpleMessage("言語"),
    "layout": MessageLookupByLibrary.simpleMessage("レイアウト"),
    "light": MessageLookupByLibrary.simpleMessage("ライト"),
    "list": MessageLookupByLibrary.simpleMessage("リスト"),
    "listen": MessageLookupByLibrary.simpleMessage("リスン"),
    "liveConnectionList": MessageLookupByLibrary.simpleMessage("リアルタイム接続一覧"),
    "liveConnectionsCount": m20,
    "liveConnectionsFailed": MessageLookupByLibrary.simpleMessage(
      "リアルタイム接続を読み込めません。後でもう一度お試しください",
    ),
    "loadTest": MessageLookupByLibrary.simpleMessage("読み込みテスト"),
    "loading": MessageLookupByLibrary.simpleMessage("読み込み中..."),
    "loadingPaymentMethods": MessageLookupByLibrary.simpleMessage(
      "支払い方法を読み込んでいます…",
    ),
    "local": MessageLookupByLibrary.simpleMessage("ローカル"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage("ローカルにデータをバックアップ"),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Location Permission",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "位置情報の権限が拒否されたため、現在の Wi-Fi 名を取得できません。システム設定で位置情報の権限を手動で有効にしてください。",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "According to system requirements, obtaining the Wi-Fi name requires you to grant location permission.",
    ),
    "locationPermissionGuide": m21,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Location Permission Required",
    ),
    "log": MessageLookupByLibrary.simpleMessage("ログ"),
    "logLevel": MessageLookupByLibrary.simpleMessage("ログレベル"),
    "logcat": MessageLookupByLibrary.simpleMessage("ログキャット"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("無効化するとログエントリを非表示"),
    "loggedIn": MessageLookupByLibrary.simpleMessage("ログイン済み"),
    "loggingIn": MessageLookupByLibrary.simpleMessage("ログインしています…"),
    "login": MessageLookupByLibrary.simpleMessage("ログイン"),
    "loginEndpoint": MessageLookupByLibrary.simpleMessage("ログイン接続先"),
    "loginEndpointLabel": m22,
    "loginFailed": MessageLookupByLibrary.simpleMessage(
      "ログインに失敗しました。しばらくしてから再試行してください",
    ),
    "loginSessionExpired": MessageLookupByLibrary.simpleMessage(
      "ログインの有効期限が切れました。再度ログインしてください",
    ),
    "loginWelcome": MessageLookupByLibrary.simpleMessage(
      "おかえりなさい。アカウントにログインしてください",
    ),
    "logoutAccount": MessageLookupByLibrary.simpleMessage("ログアウト"),
    "logoutConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "この端末に保存されたログイン情報は削除されます。",
    ),
    "logoutConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "このアカウントからログアウトしますか？",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("ログ"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("ログキャプチャ記録"),
    "logsTest": MessageLookupByLibrary.simpleMessage("ログテスト"),
    "loopback": MessageLookupByLibrary.simpleMessage("ループバック解除ツール"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage("UWPループバック解除用"),
    "loose": MessageLookupByLibrary.simpleMessage("疎"),
    "lowestLatency": MessageLookupByLibrary.simpleMessage("最小遅延"),
    "manageChainProxy": MessageLookupByLibrary.simpleMessage("チェーンを管理"),
    "manualSelection": MessageLookupByLibrary.simpleMessage("手動選択"),
    "matchContent": MessageLookupByLibrary.simpleMessage("一致内容"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("送信元IPをマッチング"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("最大失敗回数"),
    "memberValidUntil": MessageLookupByLibrary.simpleMessage("会員有効期限"),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("メモリ情報"),
    "messageTest": MessageLookupByLibrary.simpleMessage("メッセージテスト"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("これはメッセージです。"),
    "min": MessageLookupByLibrary.simpleMessage("最小化"),
    "mine": MessageLookupByLibrary.simpleMessage("マイページ"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("終了時に最小化"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "システムの終了イベントを変更",
    ),
    "minutesAgo": m23,
    "mixedPort": MessageLookupByLibrary.simpleMessage("混合ポート"),
    "mixedPortSharedDescription": MessageLookupByLibrary.simpleMessage(
      "HTTP と SOCKS5 の共通ポート",
    ),
    "mode": MessageLookupByLibrary.simpleMessage("モード"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("モノクローム"),
    "monthlyBilling": MessageLookupByLibrary.simpleMessage("月払い"),
    "monthsAgo": m24,
    "more": MessageLookupByLibrary.simpleMessage("詳細"),
    "myInvitation": MessageLookupByLibrary.simpleMessage("招待報酬"),
    "myOrders": MessageLookupByLibrary.simpleMessage("注文履歴"),
    "myWallet": MessageLookupByLibrary.simpleMessage("ウォレット"),
    "name": MessageLookupByLibrary.simpleMessage("名前"),
    "nameserver": MessageLookupByLibrary.simpleMessage("ネームサーバー"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage("ドメイン解決用"),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage("ネームサーバーポリシー"),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "対応するネームサーバーポリシーを指定",
    ),
    "network": MessageLookupByLibrary.simpleMessage("ネットワーク"),
    "networkDesc": MessageLookupByLibrary.simpleMessage("ネットワーク関連設定の変更"),
    "networkDetection": MessageLookupByLibrary.simpleMessage("ネットワーク検出"),
    "networkDiagnosticConfigDnsFailed": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシは外部接続できますが、設定ドメインを名前解決できません",
    ),
    "networkDiagnosticConfigDomains": MessageLookupByLibrary.simpleMessage(
      "設定ドメイン",
    ),
    "networkDiagnosticConfigDomainsResult": m25,
    "networkDiagnosticCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "プロキシコアが起動していません",
    ),
    "networkDiagnosticInternetFailed": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシ経由のインターネット接続に失敗しました",
    ),
    "networkDiagnosticInternetSuccess": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシ経由のインターネット接続に成功しました",
    ),
    "networkDiagnosticLocalProxyPort": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシポート",
    ),
    "networkDiagnosticNoProfile": MessageLookupByLibrary.simpleMessage(
      "利用可能な購読設定がありません。再ログインするか購読を更新してください",
    ),
    "networkDiagnosticNodeInternet": MessageLookupByLibrary.simpleMessage(
      "ノードの実インターネット接続",
    ),
    "networkDiagnosticNodeUnavailable": MessageLookupByLibrary.simpleMessage(
      "ローカルポートは正常ですが、現在のノードはインターネットに接続できません",
    ),
    "networkDiagnosticPortListening": m26,
    "networkDiagnosticPortNotListening": MessageLookupByLibrary.simpleMessage(
      "コアは起動していますが、ローカルプロキシポートが待受していません",
    ),
    "networkDiagnosticPortUnavailable": m27,
    "networkDiagnosticProxyFailure": m28,
    "networkDiagnosticProxyVerified": m29,
    "networkDiagnosticSuccess": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシ経由の外部接続に成功しました。各アプリや TUN の通信経路は未確認です",
    ),
    "networkDiagnosticSystemProxyInvalid": MessageLookupByLibrary.simpleMessage(
      "Windows システムプロキシが正しく設定されていません",
    ),
    "networkDiagnosticTrafficEntryMissing":
        MessageLookupByLibrary.simpleMessage(
          "ノードは利用できますが、システムプロキシと TUN が無効なため、アプリの通信はコアに入りません",
        ),
    "networkDiagnosticWindowsSystemProxy": MessageLookupByLibrary.simpleMessage(
      "Windows システムプロキシ",
    ),
    "networkException": MessageLookupByLibrary.simpleMessage(
      "ネットワーク例外、接続を確認してもう一度お試しください",
    ),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("ネットワーク速度"),
    "networkType": MessageLookupByLibrary.simpleMessage("ネットワーク種別"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("ニュートラル"),
    "newPassword": MessageLookupByLibrary.simpleMessage("新しいパスワード"),
    "nextAnnouncement": MessageLookupByLibrary.simpleMessage("次へ"),
    "nextPage": MessageLookupByLibrary.simpleMessage("次へ"),
    "nextPlanResetAt": m30,
    "noActiveConnections": MessageLookupByLibrary.simpleMessage(
      "アクティブな接続はありません。VPN を開始して通信するとここに表示されます",
    ),
    "noActivePlan": MessageLookupByLibrary.simpleMessage("有効なプランなし"),
    "noAnnouncements": MessageLookupByLibrary.simpleMessage("お知らせはありません"),
    "noChainProxy": MessageLookupByLibrary.simpleMessage("チェーンプロキシがありません"),
    "noChainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "SOCKS5 または HTTP プロキシを追加してください。",
    ),
    "noCommissionRecords": MessageLookupByLibrary.simpleMessage("報酬履歴はありません"),
    "noData": MessageLookupByLibrary.simpleMessage("データなし"),
    "noHandlingFee": MessageLookupByLibrary.simpleMessage("手数料なし"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("ホットキーなし"),
    "noInfo": MessageLookupByLibrary.simpleMessage("情報なし"),
    "noInviteCodes": MessageLookupByLibrary.simpleMessage(
      "招待コードはありません。上のボタンから作成してください。",
    ),
    "noLimit": MessageLookupByLibrary.simpleMessage("無制限"),
    "noLongerRemind": MessageLookupByLibrary.simpleMessage("今後表示しない"),
    "noMatchingConnections": MessageLookupByLibrary.simpleMessage(
      "一致する接続がありません",
    ),
    "noNetwork": MessageLookupByLibrary.simpleMessage("ネットワークなし"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("ネットワークなしアプリ"),
    "noOrders": MessageLookupByLibrary.simpleMessage("注文履歴はありません"),
    "noPaymentMethods": MessageLookupByLibrary.simpleMessage(
      "現在利用可能な支払い方法はありません",
    ),
    "noPaymentRequired": MessageLookupByLibrary.simpleMessage("この注文に支払いは不要です"),
    "noProfileForRule": MessageLookupByLibrary.simpleMessage(
      "ルールを保存できる現在のプロファイルがありません",
    ),
    "noProxyGroupForFallback": MessageLookupByLibrary.simpleMessage(
      "グローバルのフォールバックルールに使用できるプロキシグループがありません",
    ),
    "noRecords": MessageLookupByLibrary.simpleMessage("履歴なし"),
    "noResolve": MessageLookupByLibrary.simpleMessage("IPを解決しない"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage("ホスト名を解決しない"),
    "noTrafficRecords": MessageLookupByLibrary.simpleMessage("今月の通信履歴はありません"),
    "nodeAvailable": MessageLookupByLibrary.simpleMessage("利用可能"),
    "nodeBackendOffline": MessageLookupByLibrary.simpleMessage("サーバー停止中"),
    "nodeBackendOnline": MessageLookupByLibrary.simpleMessage("サーバー稼働中"),
    "nodeLabel": MessageLookupByLibrary.simpleMessage("ノード"),
    "nodeLocallyUnreachable": MessageLookupByLibrary.simpleMessage(
      "現在の回線では到達不可",
    ),
    "nodeNetworkFluctuating": MessageLookupByLibrary.simpleMessage("ネットワーク不安定"),
    "nodeStatus": MessageLookupByLibrary.simpleMessage("ノード状態"),
    "nodeStatusSubtitle": MessageLookupByLibrary.simpleMessage(
      "最適なノードを選び、高速で安定した接続を利用できます",
    ),
    "nodeStatusUnknown": MessageLookupByLibrary.simpleMessage("状態不明"),
    "nodesCount": m31,
    "none": MessageLookupByLibrary.simpleMessage("なし"),
    "notEnabled": MessageLookupByLibrary.simpleMessage("未設定"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "現在のプロキシグループは選択できません",
    ),
    "notTested": MessageLookupByLibrary.simpleMessage("未測定"),
    "notificationSettings": MessageLookupByLibrary.simpleMessage("通知設定"),
    "notificationSettingsSaved": MessageLookupByLibrary.simpleMessage(
      "通知設定を保存しました",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルがありません。追加してください",
    ),
    "nullTip": m32,
    "numberTip": m33,
    "offline": MessageLookupByLibrary.simpleMessage("オフライン"),
    "offlineCacheContinues": MessageLookupByLibrary.simpleMessage(
      "既存のキャッシュはホーム画面とノード表示で引き続き使用できます。",
    ),
    "offlineCacheUnavailable": MessageLookupByLibrary.simpleMessage(
      "過去3日以内に確認された有効なサブスクリプションキャッシュがありません",
    ),
    "offlineEntry": MessageLookupByLibrary.simpleMessage("ローカルキャッシュで続行"),
    "offlineEntryHint": MessageLookupByLibrary.simpleMessage(
      "最後に確認されたサブスクリプションとノードを使用します",
    ),
    "offlineEntryUnavailable": MessageLookupByLibrary.simpleMessage(
      "利用可能なオフラインキャッシュがありません",
    ),
    "offlineMode": MessageLookupByLibrary.simpleMessage("オフラインモード"),
    "offlineModeBanner": MessageLookupByLibrary.simpleMessage(
      "オフラインモードが有効です。ローカルキャッシュを表示しています。",
    ),
    "offlineModeDescriptionTitle": MessageLookupByLibrary.simpleMessage(
      "オフラインモードについて",
    ),
    "offlineModeEnabled": MessageLookupByLibrary.simpleMessage("有効"),
    "offlineNetworkTools": MessageLookupByLibrary.simpleMessage(
      "アカウントログインを必要としないネットワークツールは引き続き使用できます。",
    ),
    "offlineNoUpdates": MessageLookupByLibrary.simpleMessage(
      "プラン、招待、サブスクリプション、ユーザー情報は更新されません。",
    ),
    "oldPassword": MessageLookupByLibrary.simpleMessage("現在のパスワード"),
    "onDemand": MessageLookupByLibrary.simpleMessage("On Demand"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "Configure the program running state for specific scenarios",
    ),
    "oneTimeBilling": MessageLookupByLibrary.simpleMessage("買い切り"),
    "oneTimePlans": MessageLookupByLibrary.simpleMessage("買い切り"),
    "online": MessageLookupByLibrary.simpleMessage("オンライン"),
    "onlineFeaturesUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "この機能を使用するにはオンラインモードに戻してください",
    ),
    "onlineSupport": MessageLookupByLibrary.simpleMessage("サポート"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("アイコンのみ"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage("プロキシのみ統計"),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとプロキシトラフィックのみ統計",
    ),
    "optimizationComplete": MessageLookupByLibrary.simpleMessage("最適化が完了しました"),
    "optimizationDownload": MessageLookupByLibrary.simpleMessage(
      "ダウンロード速度を測定しています",
    ),
    "optimizationFailed": MessageLookupByLibrary.simpleMessage(
      "利用可能な Cloudflare IP が見つかりません。接続を確認して再試行してください",
    ),
    "optimizationLatency": MessageLookupByLibrary.simpleMessage("接続遅延を測定しています"),
    "optimizationPreparing": MessageLookupByLibrary.simpleMessage(
      "Cloudflare 候補 IP を読み込んでいます",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("オプション"),
    "options": MessageLookupByLibrary.simpleMessage("オプション"),
    "orderAmount": MessageLookupByLibrary.simpleMessage("金額"),
    "orderCancelled": MessageLookupByLibrary.simpleMessage("注文はキャンセルされました"),
    "orderCancelledSuccess": MessageLookupByLibrary.simpleMessage(
      "注文をキャンセルしました",
    ),
    "orderCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "プランと通信量リセットの注文、支払い、開通状況を確認します",
    ),
    "orderDetailsTitle": MessageLookupByLibrary.simpleMessage("注文詳細"),
    "orderListFailed": MessageLookupByLibrary.simpleMessage("注文履歴を読み込めませんでした"),
    "orderNumber": MessageLookupByLibrary.simpleMessage("注文番号"),
    "orderPageIndicator": m34,
    "orderPeriod": MessageLookupByLibrary.simpleMessage("期間"),
    "orderPlan": MessageLookupByLibrary.simpleMessage("プラン"),
    "orderStatusCancelled": MessageLookupByLibrary.simpleMessage("キャンセル済み"),
    "orderStatusCompleted": MessageLookupByLibrary.simpleMessage("完了"),
    "orderStatusPending": MessageLookupByLibrary.simpleMessage("支払い待ち"),
    "orderStatusProcessing": MessageLookupByLibrary.simpleMessage("開通処理中"),
    "orderStatusUnknown": MessageLookupByLibrary.simpleMessage("不明"),
    "organization": MessageLookupByLibrary.simpleMessage("組織"),
    "other": MessageLookupByLibrary.simpleMessage("その他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("その他の貢献者"),
    "otherTrafficPolicy": MessageLookupByLibrary.simpleMessage("その他の通信ポリシー"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("アウトバウンドモード"),
    "override": MessageLookupByLibrary.simpleMessage("上書き"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("DNS上書き"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとプロファイルのDNS設定を上書き",
    ),
    "overrideMode": MessageLookupByLibrary.simpleMessage("上書きモード"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("上書きスクリプト"),
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("カスタム"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "カスタムモード、プロキシグループとルールを完全にカスタマイズ可能",
    ),
    "paidAt": MessageLookupByLibrary.simpleMessage("支払い日時"),
    "palette": MessageLookupByLibrary.simpleMessage("パレット"),
    "password": MessageLookupByLibrary.simpleMessage("パスワード"),
    "passwordChanged": MessageLookupByLibrary.simpleMessage("パスワードを変更しました"),
    "passwordResetFailed": MessageLookupByLibrary.simpleMessage(
      "パスワードの再設定に失敗しました。後でもう一度お試しください",
    ),
    "passwordResetSuccess": MessageLookupByLibrary.simpleMessage(
      "パスワードを再設定しました。新しいパスワードでログインしてください",
    ),
    "passwordTooShort": MessageLookupByLibrary.simpleMessage(
      "パスワードは8文字以上で入力してください",
    ),
    "passwordsDoNotMatch": MessageLookupByLibrary.simpleMessage("パスワードが一致しません"),
    "paste": MessageLookupByLibrary.simpleMessage("貼り付け"),
    "paymentFailed": MessageLookupByLibrary.simpleMessage("支払いが完了していません"),
    "paymentMethod": MessageLookupByLibrary.simpleMessage("支払い方法"),
    "paymentSecurityHint": MessageLookupByLibrary.simpleMessage(
      "注文とQRコードはXBoard決済APIからリアルタイムで生成されます",
    ),
    "paymentStaysInApp": MessageLookupByLibrary.simpleMessage(
      "決済QRコードはアプリ内に安全に表示されます",
    ),
    "paymentSuccessful": MessageLookupByLibrary.simpleMessage("支払いが完了しました"),
    "paymentSuccessfulHint": MessageLookupByLibrary.simpleMessage(
      "プランを有効化しています。しばらくしてから購読を更新してください",
    ),
    "payoutTime": MessageLookupByLibrary.simpleMessage("支給日時"),
    "pendingCommission": MessageLookupByLibrary.simpleMessage("確認中の報酬"),
    "pendingTest": MessageLookupByLibrary.simpleMessage("未判定"),
    "peopleCount": m35,
    "personalCenter": MessageLookupByLibrary.simpleMessage("アカウント"),
    "planCatalogEmpty": MessageLookupByLibrary.simpleMessage(
      "現在購入できるプランはありません",
    ),
    "planCatalogFailed": MessageLookupByLibrary.simpleMessage("プランを読み込めませんでした"),
    "planDevicesLabel": MessageLookupByLibrary.simpleMessage("端末"),
    "planSpeedLabel": MessageLookupByLibrary.simpleMessage("速度"),
    "planStoreSubtitle": MessageLookupByLibrary.simpleMessage(
      "安全で高速・安定したグローバル接続",
    ),
    "planTrafficLabel": MessageLookupByLibrary.simpleMessage("通信量"),
    "platformCount": MessageLookupByLibrary.simpleMessage("サービス"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "WebDAVをバインドしてください",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "スクリプト名を入力してください",
    ),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "管理者パスワードを入力",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "有効なQRコードをアップロードしてください",
    ),
    "pleaseWait": MessageLookupByLibrary.simpleMessage(
      "しばらくお待ちください。重複送信しないでください",
    ),
    "popularApps": MessageLookupByLibrary.simpleMessage("人気アプリ"),
    "popularAppsDescription": MessageLookupByLibrary.simpleMessage(
      "便利なクライアントや補助アプリを確認します",
    ),
    "port": MessageLookupByLibrary.simpleMessage("ポート"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("別のポートを入力してください"),
    "portTip": m36,
    "practicalTools": MessageLookupByLibrary.simpleMessage("ユーティリティ"),
    "practicalToolsSubtitle": MessageLookupByLibrary.simpleMessage(
      "ネットワークサービスをより快適に使うための便利なツール",
    ),
    "preferH3Desc": MessageLookupByLibrary.simpleMessage("DOHのHTTP/3を優先使用"),
    "preferredNodes": MessageLookupByLibrary.simpleMessage("おすすめノード"),
    "prerequisites": MessageLookupByLibrary.simpleMessage("Prerequisites"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("キーボードを押してください"),
    "preview": MessageLookupByLibrary.simpleMessage("プレビュー"),
    "previousAnnouncement": MessageLookupByLibrary.simpleMessage("前へ"),
    "previousPage": MessageLookupByLibrary.simpleMessage("前へ"),
    "process": MessageLookupByLibrary.simpleMessage("プロセス"),
    "profile": MessageLookupByLibrary.simpleMessage("プロファイル"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("有効な間隔形式を入力してください"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("自動更新間隔を入力してください"),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "プロファイルが変更されました。自動更新を無効化しますか？",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイル名を入力してください",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "有効なプロファイルURLを入力してください",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルURLを入力してください",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("プロファイル一覧"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("プロファイルの並び替え"),
    "project": MessageLookupByLibrary.simpleMessage("プロジェクト"),
    "protocolLabel": MessageLookupByLibrary.simpleMessage("プロトコル"),
    "providers": MessageLookupByLibrary.simpleMessage("プロバイダー"),
    "provinceCity": MessageLookupByLibrary.simpleMessage("都道府県/都市"),
    "proxies": MessageLookupByLibrary.simpleMessage("プロキシ"),
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("プロキシが空です"),
    "proxyAccessAddress": MessageLookupByLibrary.simpleMessage("ローカルプロキシアドレス"),
    "proxyChains": MessageLookupByLibrary.simpleMessage("プロキシチェーン"),
    "proxyDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "選択されたプロキシに異常があることを検出しました",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("プロキシフィルター"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループ"),
    "proxyGroupDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "現在のプロキシグループが異常であることを検出しました",
    ),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage("プロキシグループが空です"),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "プロキシグループ名が重複しています",
    ),
    "proxyGroupNameEmpty": MessageLookupByLibrary.simpleMessage(
      "プロキシグループ名は空にできません",
    ),
    "proxyNameDuplicate": MessageLookupByLibrary.simpleMessage("この名前はすでに存在します"),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("プロキシネームサーバー"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "プロキシノード解決用ドメイン",
    ),
    "proxyNeededChooseNode": MessageLookupByLibrary.simpleMessage(
      "プロキシが必要：ノード一覧から DIRECT 以外を選択します。",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("プロキシポート"),
    "proxyProtocolMismatch": MessageLookupByLibrary.simpleMessage(
      "プロトコルが違います。検出結果:",
    ),
    "proxyProviderDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "選択されたプロキシプロバイダーに異常があることを検出しました",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("プロキシプロバイダー"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "プロキシプロバイダーが空です",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "プロキシプロバイダーは空にできません",
    ),
    "proxyServer": MessageLookupByLibrary.simpleMessage("サーバー"),
    "proxySettings": MessageLookupByLibrary.simpleMessage("プロキシ設定"),
    "proxySettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシサービスを管理します",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("プロキシタイプ"),
    "proxyValidationFailed": MessageLookupByLibrary.simpleMessage(
      "接続できません。サーバー、ポート、認証情報を確認してください",
    ),
    "pruneCache": MessageLookupByLibrary.simpleMessage("キャッシュの削除"),
    "publicIp": MessageLookupByLibrary.simpleMessage("公開 IP"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("プラン購入"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("純黒モード"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QRコード"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage("QRコードをスキャンしてプロファイルを取得"),
    "qualityNodes": MessageLookupByLibrary.simpleMessage("高品質ノード"),
    "quarterlyBilling": MessageLookupByLibrary.simpleMessage("3か月"),
    "queryNow": MessageLookupByLibrary.simpleMessage("今すぐ検索"),
    "quickFill": MessageLookupByLibrary.simpleMessage("クイック入力"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("レインボー"),
    "reachable": MessageLookupByLibrary.simpleMessage("接続可能"),
    "realTimeConnections": MessageLookupByLibrary.simpleMessage("リアルタイム接続"),
    "realTimeConnectionsSubtitle": MessageLookupByLibrary.simpleMessage(
      "VPN 高速化が有効で、ネットワーク接続を保護しています",
    ),
    "recurringPlans": MessageLookupByLibrary.simpleMessage("定期"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redirポート"),
    "redo": MessageLookupByLibrary.simpleMessage("やり直す"),
    "refreshApiStatus": MessageLookupByLibrary.simpleMessage("API 接続状態を更新"),
    "refreshConfiguration": MessageLookupByLibrary.simpleMessage("設定を更新"),
    "refreshData": MessageLookupByLibrary.simpleMessage("データを更新"),
    "refreshNodes": MessageLookupByLibrary.simpleMessage("更新"),
    "refreshSubscription": MessageLookupByLibrary.simpleMessage("購読を更新"),
    "region": MessageLookupByLibrary.simpleMessage("地域"),
    "registerAccount": MessageLookupByLibrary.simpleMessage("アカウント登録"),
    "registerAction": MessageLookupByLibrary.simpleMessage("登録"),
    "registeredUsers": MessageLookupByLibrary.simpleMessage("登録ユーザー数"),
    "registrationApiPending": MessageLookupByLibrary.simpleMessage(
      "登録APIはまだ接続されていません",
    ),
    "registrationFailed": MessageLookupByLibrary.simpleMessage(
      "登録に失敗しました。しばらくしてから再試行してください",
    ),
    "registrationSuccess": MessageLookupByLibrary.simpleMessage("登録が完了しました"),
    "reject": MessageLookupByLibrary.simpleMessage("拒否"),
    "remainingCommission": MessageLookupByLibrary.simpleMessage("利用可能な報酬"),
    "remainingTraffic": MessageLookupByLibrary.simpleMessage("残り通信量"),
    "remainingTrafficLabel": MessageLookupByLibrary.simpleMessage("残り"),
    "rememberMe": MessageLookupByLibrary.simpleMessage("ログイン情報を保存"),
    "rememberedPassword": MessageLookupByLibrary.simpleMessage(
      "パスワードを思い出しましたか？",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("リモート"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVにデータをバックアップ",
    ),
    "remoteDestination": MessageLookupByLibrary.simpleMessage("リモート宛先"),
    "remove": MessageLookupByLibrary.simpleMessage("削除"),
    "rename": MessageLookupByLibrary.simpleMessage("リネーム"),
    "renewPlanAction": MessageLookupByLibrary.simpleMessage("更新"),
    "renewalDoesNotResetTraffic": MessageLookupByLibrary.simpleMessage(
      "更新注文ではプランの有効期限のみが延長され、使用済み通信量はリセットされません。通信量を復元する場合は「通信量をリセット」を選択してください。",
    ),
    "renewalNoticeTitle": MessageLookupByLibrary.simpleMessage("更新について"),
    "renewalUnavailable": MessageLookupByLibrary.simpleMessage(
      "現在のプランは更新に対応していません",
    ),
    "request": MessageLookupByLibrary.simpleMessage("リクエスト"),
    "requestFailed": MessageLookupByLibrary.simpleMessage(
      "リクエストに失敗しました。後でもう一度お試しください",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("リクエスト"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage("最近のリクエスト記録を表示"),
    "requiredField": MessageLookupByLibrary.simpleMessage("必須項目です"),
    "rerunOptimization": MessageLookupByLibrary.simpleMessage("再検索"),
    "reset": MessageLookupByLibrary.simpleMessage("リセット"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "現在のページに変更があります。リセットしてもよろしいですか？",
    ),
    "resetPasswordAction": MessageLookupByLibrary.simpleMessage("パスワードを再設定"),
    "resetSubscription": MessageLookupByLibrary.simpleMessage("購読情報をリセット"),
    "resetSubscriptionConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "以前のURLは直ちに無効になり、すべての端末で再同期が必要です。",
    ),
    "resetSubscriptionConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "購読情報をリセットしますか？",
    ),
    "resetSubscriptionDescription": MessageLookupByLibrary.simpleMessage(
      "購読情報の漏えいや異常がある場合、新しい購読URLを生成します",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("リセットを確定"),
    "resetTrafficAction": MessageLookupByLibrary.simpleMessage("通信量をリセット"),
    "resettingPassword": MessageLookupByLibrary.simpleMessage("再設定中…"),
    "resources": MessageLookupByLibrary.simpleMessage("リソース"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage("外部リソース関連情報"),
    "respectRules": MessageLookupByLibrary.simpleMessage("ルール尊重"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS接続がルールに従う（proxy-server-nameserverの設定が必要）",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("再起動"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage("コアを再起動してもよろしいですか？"),
    "restore": MessageLookupByLibrary.simpleMessage("復元"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("すべてのデータを復元する"),
    "restoreException": MessageLookupByLibrary.simpleMessage("復元例外"),
    "restoreFromFileDesc": MessageLookupByLibrary.simpleMessage(
      "ファイルを介してデータを復元する",
    ),
    "restoreFromWebDAVDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVを介してデータを復元する",
    ),
    "restoreOnline": MessageLookupByLibrary.simpleMessage("オンラインモードに戻す"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage("設定ファイルのみを復元する"),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("復元ストラテジー"),
    "restoreStrategy_compatible": MessageLookupByLibrary.simpleMessage("互換"),
    "restoreStrategy_override": MessageLookupByLibrary.simpleMessage("上書き"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage("復元に成功しました"),
    "restoringOnline": MessageLookupByLibrary.simpleMessage("オンラインモードを復元中…"),
    "retry": MessageLookupByLibrary.simpleMessage("再試行"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("ルートアドレス"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage("ルートアドレスを設定"),
    "routeMode": MessageLookupByLibrary.simpleMessage("ルートモード"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage(
      "プライベートルートをバイパス",
    ),
    "routeMode_config": MessageLookupByLibrary.simpleMessage("設定を使用"),
    "ru": MessageLookupByLibrary.simpleMessage("ロシア語"),
    "rule": MessageLookupByLibrary.simpleMessage("ルール"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage("論理ルール AND"),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "完全なドメインをマッチング",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "ドメインキーワードをマッチング",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "ワイルドカードマッチング（*と?のみサポート）",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "ドメイン接尾辞をマッチング",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "DSCPマークをマッチング (tproxy udp inboundのみ)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "宛先ポート範囲をマッチング",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "IPの国コードをマッチング",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Match domains within Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンド名をマッチング",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンドポートをマッチング",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンドタイプをマッチング",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンドユーザー名をマッチング（/で複数指定可）",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage("IPのASNをマッチング"),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "IPアドレス範囲をマッチング（IP-CIDR6はエイリアスです）",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "IPアドレス範囲をマッチング",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "IP接尾辞範囲をマッチング",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "すべてのリクエストにマッチ（条件なし）",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "TCPまたはUDPをマッチング",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage("論理ルール NOT"),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("論理ルール OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "プロセス名でマッチング（Androidではパッケージ名）",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "プロセス名正規表現でマッチング（Androidではパッケージ名）",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "フルプロセスパスでマッチング",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "プロセスパス正規表現でマッチング",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "ルールセットを参照。rule-providersの設定が必要",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPの国コードをマッチング",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPのASNをマッチング",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPアドレス範囲をマッチング",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IP接尾辞範囲をマッチング",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "送信元ポート範囲をマッチング",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "サブルールにマッチング。括弧の使用に注意",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Linux USER IDをマッチング",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("ルールが空です"),
    "ruleName": MessageLookupByLibrary.simpleMessage("ルール名"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("ルールプロバイダー"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("ルールセット"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("ルール対象"),
    "ruleType": MessageLookupByLibrary.simpleMessage("ルールタイプ"),
    "ruleTypeHelp": MessageLookupByLibrary.simpleMessage(
      "DOMAIN は完全一致、DOMAIN-SUFFIX はサブドメインも一致します",
    ),
    "runNetworkDiagnostics": MessageLookupByLibrary.simpleMessage(
      "ネットワーク診断を実行",
    ),
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("変更を保存"),
    "savedDnsServersCount": m37,
    "scanToPay": MessageLookupByLibrary.simpleMessage("スキャンして支払う"),
    "scanWithPaymentApp": MessageLookupByLibrary.simpleMessage(
      "対応する決済アプリで下のQRコードをスキャンしてください",
    ),
    "script": MessageLookupByLibrary.simpleMessage("スクリプト"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "スクリプトモード、外部拡張スクリプトを使用し、ワンクリックで設定を上書きする機能を提供",
    ),
    "search": MessageLookupByLibrary.simpleMessage("検索"),
    "searchConnectionsHint": MessageLookupByLibrary.simpleMessage(
      "ドメイン、IP、ルール、ノードを検索",
    ),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "secondsCount": m38,
    "selectAll": MessageLookupByLibrary.simpleMessage("すべて選択"),
    "selectPaymentMethod": MessageLookupByLibrary.simpleMessage("支払い方法を選択"),
    "selectProxies": MessageLookupByLibrary.simpleMessage("プロキシを選択"),
    "selectProxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループを選択"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "プロキシプロバイダーを選択",
    ),
    "selectRenewalPeriod": MessageLookupByLibrary.simpleMessage("更新期間を選択"),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage("ルールセットを選択してください"),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "分流戦略を選択してください",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage("サブルールを選択してください"),
    "selectWithdrawalMethod": MessageLookupByLibrary.simpleMessage(
      "出金方法を選択してください",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("選択済み"),
    "selectedCountTitle": m39,
    "sendVerificationCode": MessageLookupByLibrary.simpleMessage("送信"),
    "sendingVerificationCode": MessageLookupByLibrary.simpleMessage("送信中..."),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("サービス状態"),
    "settings": MessageLookupByLibrary.simpleMessage("設定"),
    "show": MessageLookupByLibrary.simpleMessage("表示"),
    "showPassword": MessageLookupByLibrary.simpleMessage("パスワードを表示"),
    "shrink": MessageLookupByLibrary.simpleMessage("縮小"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("バックグラウンド起動"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage("バックグラウンドで起動"),
    "size": MessageLookupByLibrary.simpleMessage("サイズ"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socksポート"),
    "soldOut": MessageLookupByLibrary.simpleMessage("売り切れ"),
    "sort": MessageLookupByLibrary.simpleMessage("並び替え"),
    "source": MessageLookupByLibrary.simpleMessage("ソース"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("送信元IP"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("特殊プロキシ"),
    "specialRules": MessageLookupByLibrary.simpleMessage("特殊ルール"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("速度統計"),
    "speedTest": MessageLookupByLibrary.simpleMessage("速度テスト"),
    "speedTestDescription": MessageLookupByLibrary.simpleMessage(
      "外部サービスで現在のネットワーク速度を測定します",
    ),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("分流戦略"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "分流戦略は空にできません",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs is empty"),
    "stackMode": MessageLookupByLibrary.simpleMessage("スタックモード"),
    "standard": MessageLookupByLibrary.simpleMessage("標準"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "標準モード、基本設定を上書きし、シンプルなルール追加機能を提供",
    ),
    "standardizedDelay": MessageLookupByLibrary.simpleMessage("標準 RTT"),
    "start": MessageLookupByLibrary.simpleMessage("開始"),
    "startAcceleration": MessageLookupByLibrary.simpleMessage("アクセラレート開始"),
    "startOptimization": MessageLookupByLibrary.simpleMessage("検索開始"),
    "startTest": MessageLookupByLibrary.simpleMessage("判定開始"),
    "startVpn": MessageLookupByLibrary.simpleMessage("VPNを開始中..."),
    "status": MessageLookupByLibrary.simpleMessage("ステータス"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("無効時はシステムDNSを使用"),
    "stop": MessageLookupByLibrary.simpleMessage("停止"),
    "stopAcceleration": MessageLookupByLibrary.simpleMessage("アクセラレート停止"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("VPNを停止中..."),
    "streamingExitRegion": MessageLookupByLibrary.simpleMessage("出口地域"),
    "streamingFailed": MessageLookupByLibrary.simpleMessage("接続失敗"),
    "streamingNetworkError": MessageLookupByLibrary.simpleMessage(
      "ネットワーク接続に失敗しました",
    ),
    "streamingProxyRequired": MessageLookupByLibrary.simpleMessage(
      "判定前にアクセラレーションを開始し、プロキシノードを選択してください",
    ),
    "streamingReachable": MessageLookupByLibrary.simpleMessage(
      "Web ページにアクセス可能・詳細状態は未確認",
    ),
    "streamingReachableProbeFailed": MessageLookupByLibrary.simpleMessage(
      "Web ページにアクセス可能・詳細状態は未確認",
    ),
    "streamingReachableProbeTimedOut": MessageLookupByLibrary.simpleMessage(
      "Web ページにアクセス可能・詳細判定がタイムアウト",
    ),
    "streamingRestricted": MessageLookupByLibrary.simpleMessage("地域制限あり"),
    "streamingServiceError": MessageLookupByLibrary.simpleMessage(
      "サービスで一時的なエラーが発生しています",
    ),
    "streamingTimedOut": MessageLookupByLibrary.simpleMessage(
      "判定がタイムアウトしました。再試行してください",
    ),
    "streamingUnlockTest": MessageLookupByLibrary.simpleMessage("ストリーミング利用判定"),
    "streamingUnlockTestDescription": MessageLookupByLibrary.simpleMessage(
      "現在のノードで動画・AI サービスが利用可能か確認します",
    ),
    "streamingUnlocked": MessageLookupByLibrary.simpleMessage("Web ページにアクセス可能"),
    "style": MessageLookupByLibrary.simpleMessage("スタイル"),
    "subRule": MessageLookupByLibrary.simpleMessage("サブルール"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("サブルールが空です"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage("サブルールは空にできません"),
    "submit": MessageLookupByLibrary.simpleMessage("送信"),
    "submitWithdrawalTicket": MessageLookupByLibrary.simpleMessage("出金チケットを送信"),
    "subscriptionExpiredWarning": m40,
    "subscriptionExpiringWarning": m41,
    "subscriptionImportFailed": MessageLookupByLibrary.simpleMessage(
      "購読ノードを読み込めませんでした。ネットワークを確認して再試行してください",
    ),
    "subscriptionLowTrafficWarning": m42,
    "subscriptionNormalTooltip": MessageLookupByLibrary.simpleMessage(
      "プランは正常です。クリックして詳細を表示",
    ),
    "subscriptionPlanUnavailable": MessageLookupByLibrary.simpleMessage(
      "現在のプラン情報が見つかりません。更新してからもう一度お試しください",
    ),
    "subscriptionResetSuccess": MessageLookupByLibrary.simpleMessage(
      "購読情報をリセットして同期しました",
    ),
    "subscriptionStatusNormalMessage": MessageLookupByLibrary.simpleMessage(
      "残り通信量と有効期限はいずれも正常です。",
    ),
    "subscriptionStatusNormalTitle": MessageLookupByLibrary.simpleMessage(
      "プランは正常です",
    ),
    "subscriptionWarningTitle": MessageLookupByLibrary.simpleMessage("プラン警告"),
    "subscriptionWarningTooltip": MessageLookupByLibrary.simpleMessage(
      "プランに警告があります。クリックして詳細を表示",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("一時停止中..."),
    "switchAndDirect": MessageLookupByLibrary.simpleMessage("切り替えて DIRECT を使用"),
    "switchNode": MessageLookupByLibrary.simpleMessage("ノード切替"),
    "switchToGlobalMode": MessageLookupByLibrary.simpleMessage(
      "グローバルモードに切り替える",
    ),
    "sync": MessageLookupByLibrary.simpleMessage("同期"),
    "system": MessageLookupByLibrary.simpleMessage("システム"),
    "systemApp": MessageLookupByLibrary.simpleMessage("システムアプリ"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "systemProxyApplyFailed": m43,
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "HTTPプロキシをVpnServiceに接続",
    ),
    "systemProxyDisableFailed": m44,
    "systemProxyStaleCleaned": MessageLookupByLibrary.simpleMessage(
      "前回の異常終了で残ったシステムプロキシを消去しました",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("タブ"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("タブアニメーション"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage("モバイル表示でのみ有効"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("タップして許可"),
    "targetPolicy": MessageLookupByLibrary.simpleMessage("対象ポリシー"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP並列処理"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage("TCP並列処理を許可"),
    "telegramBinding": MessageLookupByLibrary.simpleMessage("Telegram連携"),
    "telegramId": MessageLookupByLibrary.simpleMessage("Telegram ID"),
    "telegramUnboundHint": MessageLookupByLibrary.simpleMessage(
      "このアカウントはTelegramと連携されていません",
    ),
    "testAll": MessageLookupByLibrary.simpleMessage("すべて判定"),
    "testAllEndpoints": MessageLookupByLibrary.simpleMessage("すべて測定"),
    "testEndpoint": MessageLookupByLibrary.simpleMessage("測定"),
    "testInterval": MessageLookupByLibrary.simpleMessage("テスト間隔"),
    "testUrl": MessageLookupByLibrary.simpleMessage("URLテスト"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("使用時にテスト"),
    "testingStatus": MessageLookupByLibrary.simpleMessage("判定中"),
    "textScale": MessageLookupByLibrary.simpleMessage("テキストスケーリング"),
    "theme": MessageLookupByLibrary.simpleMessage("テーマ"),
    "themeColor": MessageLookupByLibrary.simpleMessage("テーマカラー"),
    "themeDesc": MessageLookupByLibrary.simpleMessage("ダークモードの設定、色の調整"),
    "themeMode": MessageLookupByLibrary.simpleMessage("テーマモード"),
    "threeYearBilling": MessageLookupByLibrary.simpleMessage("3年"),
    "tight": MessageLookupByLibrary.simpleMessage("密"),
    "time": MessageLookupByLibrary.simpleMessage("時間"),
    "timeout": MessageLookupByLibrary.simpleMessage("タイムアウト"),
    "timezoneLabel": MessageLookupByLibrary.simpleMessage("タイムゾーン"),
    "tip": MessageLookupByLibrary.simpleMessage("ヒント"),
    "todayTraffic": MessageLookupByLibrary.simpleMessage("今日の通信量"),
    "toggle": MessageLookupByLibrary.simpleMessage("トグル"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("トーンスポット"),
    "toolbox": MessageLookupByLibrary.simpleMessage("ツールボックス"),
    "tools": MessageLookupByLibrary.simpleMessage("ツール"),
    "totalCommission": MessageLookupByLibrary.simpleMessage("累計報酬"),
    "totalOrders": m45,
    "totalTrafficLabel": MessageLookupByLibrary.simpleMessage("合計"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxyポート"),
    "trafficDetailRecords": MessageLookupByLibrary.simpleMessage("通信量の詳細履歴"),
    "trafficDetails": MessageLookupByLibrary.simpleMessage("通信量"),
    "trafficDetailsSubtitle": MessageLookupByLibrary.simpleMessage(
      "通信量とネットワーク利用傾向を確認します",
    ),
    "trafficEmailReminder": MessageLookupByLibrary.simpleMessage("通信量メール通知"),
    "trafficRate": MessageLookupByLibrary.simpleMessage("倍率"),
    "trafficRecordsFailed": MessageLookupByLibrary.simpleMessage(
      "通信量データを読み込めません",
    ),
    "trafficResetBilling": MessageLookupByLibrary.simpleMessage("リセット"),
    "trafficResetUnavailable": MessageLookupByLibrary.simpleMessage(
      "現在のプランは通信量のリセットに対応していません",
    ),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("トラフィック使用量"),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage("管理者モードでのみ有効"),
    "turnOff": MessageLookupByLibrary.simpleMessage("オフ"),
    "turnOn": MessageLookupByLibrary.simpleMessage("オン"),
    "twoYearBilling": MessageLookupByLibrary.simpleMessage("2年"),
    "unbound": MessageLookupByLibrary.simpleMessage("未連携"),
    "undo": MessageLookupByLibrary.simpleMessage("元に戻す"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("統一遅延"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "ハンドシェイクなどの余分な遅延を削除",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("不明"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage("不明なネットワークエラー"),
    "unlimitedTime": MessageLookupByLibrary.simpleMessage("期限なし"),
    "unnamed": MessageLookupByLibrary.simpleMessage("無題"),
    "unreachable": MessageLookupByLibrary.simpleMessage("接続不可"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "updateAll": MessageLookupByLibrary.simpleMessage("すべて更新"),
    "upgradePlanAction": MessageLookupByLibrary.simpleMessage("アップグレード"),
    "upload": MessageLookupByLibrary.simpleMessage("アップロード"),
    "uploadSpeed": MessageLookupByLibrary.simpleMessage("アップロード速度"),
    "uploadTraffic": MessageLookupByLibrary.simpleMessage("アップロード"),
    "uploaded": MessageLookupByLibrary.simpleMessage("アップロード済み"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("URL経由でプロファイルを取得"),
    "urlTip": m46,
    "useHosts": MessageLookupByLibrary.simpleMessage("ホストを使用"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("システムホストを使用"),
    "usedTrafficLabel": MessageLookupByLibrary.simpleMessage("使用済み"),
    "userAgent": MessageLookupByLibrary.simpleMessage("ユーザーエージェント"),
    "userInfoFailed": MessageLookupByLibrary.simpleMessage(
      "アカウント情報を読み込めませんでした",
    ),
    "userMapLabel": MessageLookupByLibrary.simpleMessage("ユーザー"),
    "username": MessageLookupByLibrary.simpleMessage("ユーザー名"),
    "validatingProxy": MessageLookupByLibrary.simpleMessage("プロキシ接続を確認中…"),
    "validatingTargets": MessageLookupByLibrary.simpleMessage(
      "対象ドメインと最適 IP を検証しています",
    ),
    "value": MessageLookupByLibrary.simpleMessage("値"),
    "verificationApiPending": MessageLookupByLibrary.simpleMessage(
      "認証APIはまだ接続されていません",
    ),
    "verificationEmailSent": MessageLookupByLibrary.simpleMessage(
      "認証コードを送信しました。届かない場合は迷惑メールをご確認ください",
    ),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("ビブラント"),
    "view": MessageLookupByLibrary.simpleMessage("表示"),
    "viewApps": MessageLookupByLibrary.simpleMessage("アプリを見る"),
    "viewDetails": MessageLookupByLibrary.simpleMessage("詳細を表示"),
    "viewOrderDetails": MessageLookupByLibrary.simpleMessage("詳細を見る"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "VPN設定の変更が検出されました",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "VpnService経由で全システムトラフィックをルーティング",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage("変更はVPN再起動後に有効"),
    "waitingForPayment": MessageLookupByLibrary.simpleMessage("支払い結果を待っています"),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV設定"),
    "whatHappensAfterSwitch": MessageLookupByLibrary.simpleMessage("切り替え後の動作"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("ホワイトリストモード"),
    "withdrawalAccount": MessageLookupByLibrary.simpleMessage("受取口座"),
    "withdrawalAmount": MessageLookupByLibrary.simpleMessage("出金金額"),
    "withdrawalAmountExceeds": MessageLookupByLibrary.simpleMessage(
      "出金金額は利用可能な報酬を超えられません",
    ),
    "withdrawalAmountInvalid": MessageLookupByLibrary.simpleMessage(
      "有効な出金金額を入力してください",
    ),
    "withdrawalMethod": MessageLookupByLibrary.simpleMessage("出金方法"),
    "withdrawalMethodAlipay": MessageLookupByLibrary.simpleMessage("Alipay"),
    "withdrawalMethodBank": MessageLookupByLibrary.simpleMessage("銀行カード"),
    "withdrawalMethodUsdt": MessageLookupByLibrary.simpleMessage("USDT"),
    "withdrawalMethodWechat": MessageLookupByLibrary.simpleMessage(
      "WeChat Pay",
    ),
    "withdrawalRequestTitle": MessageLookupByLibrary.simpleMessage("報酬出金申請"),
    "withdrawalTicketCreated": MessageLookupByLibrary.simpleMessage(
      "出金チケットを送信しました。管理者の対応をお待ちください。",
    ),
    "withdrawalTicketDescription": MessageLookupByLibrary.simpleMessage(
      "送信するとシステム内にチケットが作成され、管理者が内容を確認して処理します。",
    ),
    "yearlyBilling": MessageLookupByLibrary.simpleMessage("年払い"),
    "yearsAgo": m47,
    "zh_CN": MessageLookupByLibrary.simpleMessage("簡体字中国語"),
    "zoomIn": MessageLookupByLibrary.simpleMessage("拡大"),
    "zoomOut": MessageLookupByLibrary.simpleMessage("縮小"),
  };
}
