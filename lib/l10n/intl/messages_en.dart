// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
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
  String get localeName => 'en';

  static String m0(current, total) => "${current} / ${total}";

  static String m1(index) => "API endpoint ${index}";

  static String m2(reachable, total) =>
      "${reachable}/${total} API endpoints available";

  static String m3(count) => "${count} countries & regions";

  static String m4(count) =>
      "${Intl.plural(count, one: '1 day ago', other: '${count} days ago')}";

  static String m5(label) =>
      "Are you sure you want to delete the selected ${label}?";

  static String m6(label) =>
      "Are you sure you want to delete the current ${label}?";

  static String m7(label) => "${label} details";

  static String m8(label) => "${label} cannot be empty";

  static String m9(count) => "${count} entries";

  static String m10(label) => "Current ${label} already exists";

  static String m11(name) => "${name} is already up to date";

  static String m12(name) => "${name} updated";

  static String m13(name) => "Updating ${name}...";

  static String m14(count) =>
      "${Intl.plural(count, one: '1 hour ago', other: '${count} hours ago')}";

  static String m15(count) => "${count} hours";

  static String m16(target) => "${target} is an invalid policy";

  static String m17(proxyName) => "${proxyName} is an invalid proxy";

  static String m18(providerName) =>
      "${providerName} is an invalid proxy provider";

  static String m19(subRule) => "${subRule} is an invalid SUB_RULE";

  static String m20(count) => "${count} connections";

  static String m21(appName) =>
      "1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check ${appName} in the right list\n\nAfter completing the setup, return to the app and use it normally. Thank you for your cooperation.";

  static String m22(index) => "Endpoint ${index}";

  static String m23(count) =>
      "${Intl.plural(count, one: '1 minute ago', other: '${count} minutes ago')}";

  static String m24(count) =>
      "${Intl.plural(count, one: '1 month ago', other: '${count} months ago')}";

  static String m25(reachable, total) => "${reachable}/${total} resolvable";

  static String m26(address) => "${address} is listening";

  static String m27(address) => "Cannot connect to ${address}";

  static String m28(code, stage, error) => "${code} / ${stage}${error}";

  static String m29(address) => "Readback verified ${address}";

  static String m30(date) => "Next plan reset: ${date}";

  static String m31(count) => "${count} nodes";

  static String m32(label) => "No ${label} yet";

  static String m33(label) => "${label} must be a number";

  static String m34(current, total) => "Page ${current} of ${total}";

  static String m35(count) => "${count}";

  static String m36(label) => "${label} must be between 1024 and 49151";

  static String m37(count) => "${count} saved; active when override is enabled";

  static String m38(count) => "${count} seconds";

  static String m39(count) => "${count} items have been selected";

  static String m40(date) =>
      "Your plan expired on ${date}. Renew it to continue using the service.";

  static String m41(date) =>
      "Your plan expires on ${date}, in less than 3 days. Renew it soon.";

  static String m42(remaining) =>
      "Only ${remaining} GB remains, which is below 10 GB. Purchase or renew a plan soon.";

  static String m43(code) =>
      "Could not enable the system proxy (${code}). The switch was reverted. Export logs for diagnosis";

  static String m44(code) =>
      "Could not disable the system proxy (${code}). Disable it manually in Windows Settings";

  static String m45(count) => "${count} orders";

  static String m46(label) => "${label} must be a url";

  static String m47(count) =>
      "${Intl.plural(count, one: '1 year ago', other: '${count} years ago')}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("About"),
    "acceleratorHome": MessageLookupByLibrary.simpleMessage("Accelerator"),
    "accessControl": MessageLookupByLibrary.simpleMessage("AccessControl"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Only allow selected app to enter VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Configure application access proxy",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "The selected application will be excluded from VPN",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage(
      "Access Control Settings",
    ),
    "accessTime": MessageLookupByLibrary.simpleMessage("Access time"),
    "account": MessageLookupByLibrary.simpleMessage("Account"),
    "accountBalance": MessageLookupByLibrary.simpleMessage("Account balance"),
    "accountCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "Manage your account information and security settings",
    ),
    "action": MessageLookupByLibrary.simpleMessage("Action"),
    "action_mode": MessageLookupByLibrary.simpleMessage("Switch mode"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "action_start": MessageLookupByLibrary.simpleMessage("Start/Stop"),
    "action_tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "action_view": MessageLookupByLibrary.simpleMessage("Show/Hide"),
    "actions": MessageLookupByLibrary.simpleMessage("Action"),
    "activateNow": MessageLookupByLibrary.simpleMessage("Activate now"),
    "actualConnectionDelay": MessageLookupByLibrary.simpleMessage(
      "Actual latency",
    ),
    "add": MessageLookupByLibrary.simpleMessage("Add"),
    "addProfile": MessageLookupByLibrary.simpleMessage("Add Profile"),
    "addProxies": MessageLookupByLibrary.simpleMessage("Add proxies"),
    "addProxy": MessageLookupByLibrary.simpleMessage("Add proxy"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("Add proxy group"),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Add proxy providers",
    ),
    "addRule": MessageLookupByLibrary.simpleMessage("Add rule"),
    "addSsid": MessageLookupByLibrary.simpleMessage("Add SSID"),
    "addedRules": MessageLookupByLibrary.simpleMessage("Added rules"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage(
      "Additional parameters",
    ),
    "address": MessageLookupByLibrary.simpleMessage("Address"),
    "addressHelp": MessageLookupByLibrary.simpleMessage(
      "WebDAV server address",
    ),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid WebDAV address",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage(
      "Advanced configuration",
    ),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Provide diverse configuration options",
    ),
    "advancedSettings": MessageLookupByLibrary.simpleMessage("Advanced"),
    "advancedSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Customize VPN behavior and network parameters for your connection",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("Agree"),
    "allGeodataUpdated": MessageLookupByLibrary.simpleMessage(
      "All geodata resources have been updated",
    ),
    "allPlans": MessageLookupByLibrary.simpleMessage("All"),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Allow applications to bypass VPN",
    ),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "Some apps can bypass VPN when turned on",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("AllowLan"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage(
      "Allow access proxy through the LAN",
    ),
    "alreadyHaveAccount": MessageLookupByLibrary.simpleMessage(
      "Already have an account?",
    ),
    "announcementCenter": MessageLookupByLibrary.simpleMessage(
      "Announcement center",
    ),
    "announcementPosition": m0,
    "announcementTooltip": MessageLookupByLibrary.simpleMessage(
      "View announcements",
    ),
    "announcementUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "Latest announcements are unavailable in offline mode",
    ),
    "apiEndpointApplied": MessageLookupByLibrary.simpleMessage(
      "Set as the global preferred API endpoint",
    ),
    "apiEndpointLabel": m1,
    "apiEndpointsAvailable": m2,
    "apiStatus": MessageLookupByLibrary.simpleMessage("API status"),
    "apiStatusUnavailable": MessageLookupByLibrary.simpleMessage(
      "API status is unavailable",
    ),
    "app": MessageLookupByLibrary.simpleMessage("App"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "App access control",
    ),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage(
      "Append System DNS",
    ),
    "appendSystemDnsTip": MessageLookupByLibrary.simpleMessage(
      "Forcefully append system DNS to the configuration",
    ),
    "application": MessageLookupByLibrary.simpleMessage("Application"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage(
      "Modify application related settings",
    ),
    "applyPreferredIps": MessageLookupByLibrary.simpleMessage("Apply all"),
    "asnLabel": MessageLookupByLibrary.simpleMessage("ASN"),
    "authorized": MessageLookupByLibrary.simpleMessage("Authorized"),
    "auto": MessageLookupByLibrary.simpleMessage("Auto"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage(
      "Auto check updates",
    ),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "Auto check for updates when the app starts",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Auto close connections",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Auto close connections after change node",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Auto launch"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Follow the system self startup",
    ),
    "autoRefresh": MessageLookupByLibrary.simpleMessage("Auto refresh"),
    "autoRenew": MessageLookupByLibrary.simpleMessage("Auto-renew"),
    "autoRun": MessageLookupByLibrary.simpleMessage("AutoRun"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Auto run when the application is opened",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Auto set system DNS",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Auto update"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto update interval (minutes)",
    ),
    "automaticLogin": MessageLookupByLibrary.simpleMessage(
      "Log in automatically",
    ),
    "automaticLoginUnavailable": MessageLookupByLibrary.simpleMessage(
      "Automatic login is temporarily unavailable. Log in manually or try again later",
    ),
    "automaticSelection": MessageLookupByLibrary.simpleMessage("Auto select"),
    "availabilityRate": MessageLookupByLibrary.simpleMessage("Availability"),
    "availableCommissionEmpty": MessageLookupByLibrary.simpleMessage(
      "No commission available to transfer",
    ),
    "availableCount": MessageLookupByLibrary.simpleMessage("Available"),
    "availableEndpoints": MessageLookupByLibrary.simpleMessage(
      "Available endpoints",
    ),
    "backToLogin": MessageLookupByLibrary.simpleMessage("Back to login"),
    "backup": MessageLookupByLibrary.simpleMessage("Backup"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage(
      "Backup and Restore",
    ),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "Sync data via WebDAV or files",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("Backup success"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("Basic configuration"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Modify the basic configuration globally",
    ),
    "basicInfo": MessageLookupByLibrary.simpleMessage("Basic info"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("Basic strategy"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "To ensure background operation, please disable battery optimization for this app. Tap to go to settings.",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "Affected by the system, this status may not always be accurate.",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("Bind"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("Blacklist mode"),
    "bound": MessageLookupByLibrary.simpleMessage("Bound"),
    "brandName": MessageLookupByLibrary.simpleMessage("FengWo Accelerator"),
    "buyNow": MessageLookupByLibrary.simpleMessage("Buy now"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Bypass domain"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Only takes effect when the system proxy is enabled",
    ),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "The cache is corrupt. Do you want to clear it?",
    ),
    "campusNetworkApplyFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to apply campus network mode. Check your connection and try again",
    ),
    "campusNetworkDisabled": MessageLookupByLibrary.simpleMessage(
      "Campus network mode is disabled",
    ),
    "campusNetworkEnabled": MessageLookupByLibrary.simpleMessage(
      "Campus network mode is enabled and active",
    ),
    "campusNetworkInformation": MessageLookupByLibrary.simpleMessage(
      "When disabled, CDN resolution remains in use. Enabling or switching routes automatically reloads the core configuration.",
    ),
    "campusNetworkLine": MessageLookupByLibrary.simpleMessage("Entry route"),
    "campusNetworkLine1": MessageLookupByLibrary.simpleMessage("Route 1"),
    "campusNetworkLine2": MessageLookupByLibrary.simpleMessage("Route 2"),
    "campusNetworkLine3": MessageLookupByLibrary.simpleMessage("Route 3"),
    "campusNetworkMode": MessageLookupByLibrary.simpleMessage(
      "Campus network mode",
    ),
    "campusNetworkModeSubtitle": MessageLookupByLibrary.simpleMessage(
      "Switch to dedicated entry routes on campus networks",
    ),
    "campusNetworkSwitch": MessageLookupByLibrary.simpleMessage(
      "Enable campus network mode",
    ),
    "campusNetworkSwitchDescription": MessageLookupByLibrary.simpleMessage(
      "Maps node domains to the selected entry route when enabled",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cancelOrder": MessageLookupByLibrary.simpleMessage("Cancel order"),
    "cancelOrderMessage": MessageLookupByLibrary.simpleMessage(
      "A cancelled order can no longer be paid. You can place a new order when needed.",
    ),
    "cancelOrderTitle": MessageLookupByLibrary.simpleMessage(
      "Cancel this order?",
    ),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage(
      "Cancel select all",
    ),
    "candidateCount": MessageLookupByLibrary.simpleMessage("Candidates"),
    "carrier": MessageLookupByLibrary.simpleMessage("Carrier"),
    "cfApplyFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to apply preferred CF IPs. The previous configuration was restored",
    ),
    "cfApplySuccess": MessageLookupByLibrary.simpleMessage(
      "Preferred CF IPs applied and the core configuration reloaded",
    ),
    "cfTargetMissingMessage": MessageLookupByLibrary.simpleMessage(
      "Add the node domains that CF optimization may replace to the remote configuration first.",
    ),
    "cfTargetMissingTitle": MessageLookupByLibrary.simpleMessage(
      "No target domain configured",
    ),
    "cfTargetValidationFailed": MessageLookupByLibrary.simpleMessage(
      "Preferred IPs failed TLS validation for the target domains. Nothing was changed",
    ),
    "chainProxy": MessageLookupByLibrary.simpleMessage("Chain proxy"),
    "chainProxyActive": MessageLookupByLibrary.simpleMessage(
      "Chain proxy is running",
    ),
    "chainProxyApplyFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to apply the core configuration. The previous configuration was restored",
    ),
    "chainProxyConnectivityFailed": MessageLookupByLibrary.simpleMessage(
      "Chain proxy connectivity test failed. It was disabled and the previous configuration was restored",
    ),
    "chainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "Manage an additional SOCKS5 or HTTP egress proxy",
    ),
    "chainProxyDirectModeUnsupported": MessageLookupByLibrary.simpleMessage(
      "Switch the outbound mode to Rule or Global first",
    ),
    "chainProxyDisabled": MessageLookupByLibrary.simpleMessage(
      "Chain proxy is not enabled",
    ),
    "chainProxyEnabled": MessageLookupByLibrary.simpleMessage(
      "Chain proxy started",
    ),
    "chainProxyLocked": MessageLookupByLibrary.simpleMessage(
      "Other entries are locked while a chain proxy is running",
    ),
    "chainProxyRollbackFailed": MessageLookupByLibrary.simpleMessage(
      "The chain proxy failed and the previous configuration could not be restored. Restart the app",
    ),
    "chainProxySessionNotice": MessageLookupByLibrary.simpleMessage(
      "When enabled, proxied traffic goes through the selected subscription node and then exits through this chain proxy. Only one can run at a time.",
    ),
    "chainProxyStopped": MessageLookupByLibrary.simpleMessage(
      "Chain proxy stopped",
    ),
    "changePasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Change password",
    ),
    "changePlanAction": MessageLookupByLibrary.simpleMessage("Change plan"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Check for updates"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "The current application is already the latest version",
    ),
    "checkingApiStatus": MessageLookupByLibrary.simpleMessage(
      "Checking API connectivity...",
    ),
    "checkingLoginStatus": MessageLookupByLibrary.simpleMessage(
      "Checking login status...",
    ),
    "chooseSpeedTest": MessageLookupByLibrary.simpleMessage("Choose service"),
    "clearData": MessageLookupByLibrary.simpleMessage("Clear Data"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("Export clipboard"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("Clipboard import"),
    "closeAction": MessageLookupByLibrary.simpleMessage("Close"),
    "closeAllConnections": MessageLookupByLibrary.simpleMessage(
      "Close all connections",
    ),
    "closeAllConnectionsDescription": MessageLookupByLibrary.simpleMessage(
      "All current connections will be closed. Apps may reconnect automatically.",
    ),
    "closeConnection": MessageLookupByLibrary.simpleMessage("Close connection"),
    "cloudflarePreferredIp": MessageLookupByLibrary.simpleMessage(
      "CF preferred IP",
    ),
    "cloudflarePreferredIpDescription": MessageLookupByLibrary.simpleMessage(
      "Find faster Cloudflare edge addresses for this network",
    ),
    "color": MessageLookupByLibrary.simpleMessage("Color"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Color schemes"),
    "columns": MessageLookupByLibrary.simpleMessage("Columns"),
    "commission": MessageLookupByLibrary.simpleMessage("Commission"),
    "commissionPayoutRecords": MessageLookupByLibrary.simpleMessage(
      "Commission records",
    ),
    "commissionRate": MessageLookupByLibrary.simpleMessage("Commission rate"),
    "commissionTransfer": MessageLookupByLibrary.simpleMessage("Transfer"),
    "commissionTransferConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "The available commission will move to your account balance for purchasing plans.",
    ),
    "commissionTransferConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Transfer all available commission?",
    ),
    "commissionTransferred": MessageLookupByLibrary.simpleMessage(
      "Commission transferred to account balance",
    ),
    "commissionWithdraw": MessageLookupByLibrary.simpleMessage("Withdraw"),
    "compatible": MessageLookupByLibrary.simpleMessage("Compatibility mode"),
    "completedCount": MessageLookupByLibrary.simpleMessage("Completed"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "Data detected in configuration",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Confirm"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to clear all data?",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to delete the current proxy group?",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to exit the current window?",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to force crash the core?",
    ),
    "confirmNewPassword": MessageLookupByLibrary.simpleMessage(
      "Confirm new password",
    ),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "Existing data will be overwritten after confirmation",
    ),
    "confirmPassword": MessageLookupByLibrary.simpleMessage("Confirm password"),
    "confirmReset": MessageLookupByLibrary.simpleMessage("Reset now"),
    "connected": MessageLookupByLibrary.simpleMessage("Connected"),
    "connecting": MessageLookupByLibrary.simpleMessage("Connecting..."),
    "connection": MessageLookupByLibrary.simpleMessage("Connection"),
    "connectionDetails": MessageLookupByLibrary.simpleMessage(
      "Connection details",
    ),
    "connectionRuleAlreadyExists": MessageLookupByLibrary.simpleMessage(
      "This rule already exists. The profile was reapplied",
    ),
    "connectionRuleApplied": MessageLookupByLibrary.simpleMessage(
      "Rule added and applied",
    ),
    "connectionRuleAppliedAndSwitched": MessageLookupByLibrary.simpleMessage(
      "Rule added and switched to Rule mode",
    ),
    "connectionStatus": MessageLookupByLibrary.simpleMessage(
      "Connection status",
    ),
    "connections": MessageLookupByLibrary.simpleMessage("Connections"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage(
      "View current connections data",
    ),
    "connectivity": MessageLookupByLibrary.simpleMessage("Connectivity："),
    "consumptionOnly": MessageLookupByLibrary.simpleMessage("Spending only"),
    "content": MessageLookupByLibrary.simpleMessage("Content"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Content cannot be empty",
    ),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Content"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "Control global added rules",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("Copy"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Copying environment variables",
    ),
    "copyInviteCode": MessageLookupByLibrary.simpleMessage("Copy invite code"),
    "copyLink": MessageLookupByLibrary.simpleMessage("Copy link"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Copy success"),
    "core": MessageLookupByLibrary.simpleMessage("Core"),
    "coreIpv6": MessageLookupByLibrary.simpleMessage("Core IPv6"),
    "coreIpv6Description": MessageLookupByLibrary.simpleMessage(
      "Control Mihomo top-level IPv6 support",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("Core status"),
    "countriesAndRegions": MessageLookupByLibrary.simpleMessage(
      "Countries & regions",
    ),
    "countriesCount": m3,
    "country": MessageLookupByLibrary.simpleMessage("Country"),
    "countryRegion": MessageLookupByLibrary.simpleMessage("Country/region"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("Crash detected"),
    "crashDetectedTip": MessageLookupByLibrary.simpleMessage(
      "The app crashed during the previous run. To prevent repeated crashes, the current profile has been cleared and automatic configuration setup was skipped.",
    ),
    "crashTest": MessageLookupByLibrary.simpleMessage("Crash test"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("Crash Analysis"),
    "crashlyticsTip": MessageLookupByLibrary.simpleMessage(
      "When enabled, automatically uploads crash logs without sensitive information when the app crashes",
    ),
    "create": MessageLookupByLibrary.simpleMessage("Create"),
    "createAccountSubtitle": MessageLookupByLibrary.simpleMessage(
      "Join us and start managing your network",
    ),
    "createAccountTitle": MessageLookupByLibrary.simpleMessage(
      "Create account",
    ),
    "createProfile": MessageLookupByLibrary.simpleMessage("Create Profile"),
    "createdAt": MessageLookupByLibrary.simpleMessage("Created"),
    "creatingOrder": MessageLookupByLibrary.simpleMessage("Creating order…"),
    "creationTime": MessageLookupByLibrary.simpleMessage("Creation time"),
    "currentActiveConnections": MessageLookupByLibrary.simpleMessage(
      "Active connections",
    ),
    "currentEndpoint": MessageLookupByLibrary.simpleMessage("Currently used"),
    "currentMonthTraffic": MessageLookupByLibrary.simpleMessage("This month"),
    "currentNode": MessageLookupByLibrary.simpleMessage("Current node"),
    "currentNodeDelay": MessageLookupByLibrary.simpleMessage(
      "Current node latency",
    ),
    "currentPlanLabel": MessageLookupByLibrary.simpleMessage("Current plan"),
    "custom": MessageLookupByLibrary.simpleMessage("Custom"),
    "customDnsServers": MessageLookupByLibrary.simpleMessage(
      "Custom DNS servers",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("Cut"),
    "dailyBrowsingRuleMode": MessageLookupByLibrary.simpleMessage(
      "Daily browsing: rule mode is more reliable.",
    ),
    "dark": MessageLookupByLibrary.simpleMessage("Dark"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Dashboard"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "Data changes detected, do you want to save?",
    ),
    "dataCollectionContent": MessageLookupByLibrary.simpleMessage(
      "This app uses Firebase Crashlytics to collect crash information to improve app stability.\nThe collected data includes device information and crash details, but does not contain personal sensitive data.\nYou can disable this feature in settings.",
    ),
    "dataCollectionTip": MessageLookupByLibrary.simpleMessage(
      "Data Collection Notice",
    ),
    "dataSource": MessageLookupByLibrary.simpleMessage("Data source"),
    "dateLabel": MessageLookupByLibrary.simpleMessage("Date"),
    "daysAgo": m4,
    "defaultNameserver": MessageLookupByLibrary.simpleMessage(
      "Default nameserver",
    ),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "For resolving DNS server",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
    "delay": MessageLookupByLibrary.simpleMessage("Delay"),
    "delayTest": MessageLookupByLibrary.simpleMessage("Delay Test"),
    "delete": MessageLookupByLibrary.simpleMessage("Delete"),
    "deleteMultipTip": m5,
    "deleteTip": m6,
    "desc": MessageLookupByLibrary.simpleMessage(
      "A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("Destination"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage(
      "Destination GeoIP",
    ),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage(
      "Destination IPASN",
    ),
    "details": m7,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Relying on third-party api is for reference only",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("Developer mode"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Developer mode is enabled.",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("Direct"),
    "disableProxy": MessageLookupByLibrary.simpleMessage("Stop"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("Disable UDP"),
    "disclaimer": MessageLookupByLibrary.simpleMessage("Disclaimer"),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "This software is only used for non-commercial purposes such as learning exchanges and scientific research. It is strictly prohibited to use this software for commercial purposes. Any commercial activity, if any, has nothing to do with this software.",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("Disconnected"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "Discover the new version",
    ),
    "dnsDesc": MessageLookupByLibrary.simpleMessage(
      "Update DNS related settings",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS hijacking"),
    "dnsIpv6": MessageLookupByLibrary.simpleMessage("DNS IPv6"),
    "dnsIpv6Description": MessageLookupByLibrary.simpleMessage(
      "Return IPv6 records from DNS queries",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS mode"),
    "dnsOverrideInformation": MessageLookupByLibrary.simpleMessage(
      "When enabled, the app\'s built-in DNS configuration is used instead of the profile DNS settings",
    ),
    "dnsSettings": MessageLookupByLibrary.simpleMessage("DNS settings"),
    "dnsSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Manage DNS resolution settings",
    ),
    "doNotRemindToday": MessageLookupByLibrary.simpleMessage(
      "Don\'t remind me again today",
    ),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage(
      "Do you want to pass",
    ),
    "domain": MessageLookupByLibrary.simpleMessage("Domain"),
    "domainOrService": MessageLookupByLibrary.simpleMessage("Domain / service"),
    "done": MessageLookupByLibrary.simpleMessage("Done"),
    "dontShowAgain": MessageLookupByLibrary.simpleMessage("Don\'t show again"),
    "download": MessageLookupByLibrary.simpleMessage("Download"),
    "downloadSpeed": MessageLookupByLibrary.simpleMessage("Download speed"),
    "downloadTraffic": MessageLookupByLibrary.simpleMessage("Download"),
    "downloaded": MessageLookupByLibrary.simpleMessage("Downloaded"),
    "edit": MessageLookupByLibrary.simpleMessage("Edit"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage(
      "Edit global rules",
    ),
    "editProxy": MessageLookupByLibrary.simpleMessage("Edit proxy"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("Edit proxy group"),
    "editRule": MessageLookupByLibrary.simpleMessage("Edit rule"),
    "editSsid": MessageLookupByLibrary.simpleMessage("Edit SSID"),
    "email": MessageLookupByLibrary.simpleMessage("Email"),
    "emailVerificationCode": MessageLookupByLibrary.simpleMessage(
      "Email verification code",
    ),
    "emptyTip": m8,
    "en": MessageLookupByLibrary.simpleMessage("English"),
    "enableOfflineAction": MessageLookupByLibrary.simpleMessage(
      "Enable offline mode",
    ),
    "enableOfflineDescription": MessageLookupByLibrary.simpleMessage(
      "Online sign-in validation and account refreshes will be skipped. Cached subscription, nodes, and account summary will be used instead.",
    ),
    "enableOfflineTitle": MessageLookupByLibrary.simpleMessage(
      "Enable offline mode?",
    ),
    "enableProxy": MessageLookupByLibrary.simpleMessage("Enable"),
    "enterConfirmPassword": MessageLookupByLibrary.simpleMessage(
      "Enter your password again",
    ),
    "enterEmail": MessageLookupByLibrary.simpleMessage("Enter your email"),
    "enterEmailAddress": MessageLookupByLibrary.simpleMessage(
      "Enter your email address",
    ),
    "enterInvitationCode": MessageLookupByLibrary.simpleMessage(
      "Enter an invitation code (if any)",
    ),
    "enterNewPassword": MessageLookupByLibrary.simpleMessage(
      "Enter a new password",
    ),
    "enterOldPassword": MessageLookupByLibrary.simpleMessage(
      "Enter your current password",
    ),
    "enterPassword": MessageLookupByLibrary.simpleMessage(
      "Enter your password",
    ),
    "enterVerificationCode": MessageLookupByLibrary.simpleMessage(
      "Enter the verification code",
    ),
    "enterWithdrawalAccount": MessageLookupByLibrary.simpleMessage(
      "Enter the receiving account or address",
    ),
    "enterWithdrawalAmount": MessageLookupByLibrary.simpleMessage(
      "Enter the withdrawal amount",
    ),
    "entries": MessageLookupByLibrary.simpleMessage(" entries"),
    "entriesCount": m9,
    "exclude": MessageLookupByLibrary.simpleMessage("Hidden from recent tasks"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "When the app is in the background, the app is hidden from the recent task",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage(
      "Exclude proxy filter",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Exclude SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "When connected to an excluded SSID Wi-Fi, the app running state will be automatically switched.",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("Exclude type"),
    "existsTip": m10,
    "exit": MessageLookupByLibrary.simpleMessage("Exit"),
    "expand": MessageLookupByLibrary.simpleMessage("Standard"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("Expected status"),
    "expiryEmailReminder": MessageLookupByLibrary.simpleMessage(
      "Expiration email reminder",
    ),
    "exportFile": MessageLookupByLibrary.simpleMessage("Export file"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Export logs"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Export Success"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Expressive"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "ExternalController",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "Once enabled, the Clash kernel can be controlled on port 9090",
    ),
    "externalFetch": MessageLookupByLibrary.simpleMessage("External fetch"),
    "externalLink": MessageLookupByLibrary.simpleMessage("External link"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fakeip filter"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fakeip range"),
    "fallback": MessageLookupByLibrary.simpleMessage("Fallback"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage(
      "Generally use offshore DNS",
    ),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback filter"),
    "fastestDownload": MessageLookupByLibrary.simpleMessage("Fastest download"),
    "featureComingSoon": MessageLookupByLibrary.simpleMessage(
      "This feature will be available after the server is connected",
    ),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Fidelity"),
    "file": MessageLookupByLibrary.simpleMessage("File"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("Directly upload profile"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "The file has been modified. Do you want to save the changes?",
    ),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("Find process"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "There is a certain performance loss after opening",
    ),
    "fontFamily": MessageLookupByLibrary.simpleMessage("FontFamily"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to force restart the core?",
    ),
    "forgotPassword": MessageLookupByLibrary.simpleMessage("Forgot password"),
    "forgotPasswordSubtitle": MessageLookupByLibrary.simpleMessage(
      "Reset your password and restore account access",
    ),
    "forgotPasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Recover password",
    ),
    "freeLabel": MessageLookupByLibrary.simpleMessage("Free"),
    "freeOrder": MessageLookupByLibrary.simpleMessage("Free activation"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("FruitSalad"),
    "general": MessageLookupByLibrary.simpleMessage("General"),
    "generateInviteCode": MessageLookupByLibrary.simpleMessage("Generate code"),
    "generateMihomoRule": MessageLookupByLibrary.simpleMessage(
      "Generate a Mihomo rule from this connection",
    ),
    "generatePaymentQr": MessageLookupByLibrary.simpleMessage(
      "Generate payment QR code",
    ),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("Auto Update"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto Update Interval",
    ),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "Auto update interval must be greater than 0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geo Options"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo Resources"),
    "geoSkipped": m11,
    "geoUpdated": m12,
    "geoUpdating": m13,
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Geo Low Memory Mode",
    ),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "Enabling will use the Geo low memory loader",
    ),
    "geodataSettings": MessageLookupByLibrary.simpleMessage("Geodata"),
    "geodataSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Update GeoIP and GeoSite databases",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("Geoip code"),
    "global": MessageLookupByLibrary.simpleMessage("Global"),
    "globalAccelerationNetwork": MessageLookupByLibrary.simpleMessage(
      "Global acceleration network",
    ),
    "globalModeWarningDescription": MessageLookupByLibrary.simpleMessage(
      "Global mode takes over all network traffic. The first switch uses DIRECT, then you can choose a proxy node after confirming.",
    ),
    "globalNodeDistribution": MessageLookupByLibrary.simpleMessage(
      "Global node distribution",
    ),
    "globalRuleModeSwitchHint": MessageLookupByLibrary.simpleMessage(
      "Global mode is active. Adding this rule switches to Rule mode: this connection uses the policy above and all other traffic uses your selected proxy group.",
    ),
    "go": MessageLookupByLibrary.simpleMessage("Go"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Go to download"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage(
      "Go to configure script",
    ),
    "halfYearBilling": MessageLookupByLibrary.simpleMessage("6 months"),
    "handlingFee": MessageLookupByLibrary.simpleMessage("Handling fee"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Do you want to cache the changes?",
    ),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper service unavailable; TUN mode cannot be enabled. Reinstall FlClash to restore it.",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("Hide from list"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Hide password"),
    "highestLatency": MessageLookupByLibrary.simpleMessage("Highest latency"),
    "host": MessageLookupByLibrary.simpleMessage("Host"),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("Add Hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("Hotkey conflict"),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage(
      "Hotkey Management",
    ),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "Use keyboard to control applications",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("hours"),
    "hoursAgo": m14,
    "hoursCount": m15,
    "iHavePaid": MessageLookupByLibrary.simpleMessage(
      "I have paid, refresh status",
    ),
    "icon": MessageLookupByLibrary.simpleMessage("Icon"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("Icon records"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Icon style"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("Icon URL"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Ignore Battery Optimization",
    ),
    "import": MessageLookupByLibrary.simpleMessage("Import"),
    "importFile": MessageLookupByLibrary.simpleMessage("Import from file"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "importUrl": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "inAppPayment": MessageLookupByLibrary.simpleMessage("In-app payment"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage(
      "Include all proxies",
    ),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "Import all proxies not containing proxy groups, additional proxy groups can be added below",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Include all proxy providers",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "When enabled, it will override the imported proxy providers",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("Long term effective"),
    "init": MessageLookupByLibrary.simpleMessage("Init"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage(
      "Please enter the correct hotkey",
    ),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "Input proxy group name",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage(
      "Input rule content",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage(
      "Intelligent selection",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Internet"),
    "interval": MessageLookupByLibrary.simpleMessage("Interval"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Intranet IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage(
      "Invalid backup file",
    ),
    "invalidEmail": MessageLookupByLibrary.simpleMessage(
      "Enter a valid email address",
    ),
    "invalidEmailAccount": MessageLookupByLibrary.simpleMessage(
      "Enter a valid email account",
    ),
    "invalidPolicy": m16,
    "invalidPort": MessageLookupByLibrary.simpleMessage("Enter a valid port"),
    "invalidProxy": m17,
    "invalidProxyProvider": m18,
    "invalidSubRule": m19,
    "invitationCode": MessageLookupByLibrary.simpleMessage("Invitation code"),
    "invitationCodeOptional": MessageLookupByLibrary.simpleMessage(
      "Invitation code (optional)",
    ),
    "invitationCodeRequired": MessageLookupByLibrary.simpleMessage(
      "Enter your invitation code",
    ),
    "inviteCode": MessageLookupByLibrary.simpleMessage("Invite code"),
    "inviteCodeCopied": MessageLookupByLibrary.simpleMessage(
      "Invite code copied",
    ),
    "inviteCodeDescription": MessageLookupByLibrary.simpleMessage(
      "Share your invite code. You earn commission after a friend signs up and purchases a plan.",
    ),
    "inviteCodeGenerated": MessageLookupByLibrary.simpleMessage(
      "Invite code generated",
    ),
    "inviteCodeManagement": MessageLookupByLibrary.simpleMessage(
      "Invite code management",
    ),
    "inviteHeroSubtitle": MessageLookupByLibrary.simpleMessage(
      "Invite more, earn more — no reward limit!",
    ),
    "inviteHeroTitle": MessageLookupByLibrary.simpleMessage(
      "Invite friends, earn rewards",
    ),
    "inviteLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to load invite data",
    ),
    "invitePromotion": MessageLookupByLibrary.simpleMessage("Invite rewards"),
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP address"),
    "ipLookup": MessageLookupByLibrary.simpleMessage("IP lookup"),
    "ipLookupDescription": MessageLookupByLibrary.simpleMessage(
      "View location, carrier, and other public IP details",
    ),
    "ipLookupFailed": MessageLookupByLibrary.simpleMessage(
      "IP lookup failed. Check your connection and try again",
    ),
    "ipcidr": MessageLookupByLibrary.simpleMessage("Ipcidr"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "When turned on it will be able to receive IPv6 traffic",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "Allow IPv6 inbound",
    ),
    "ipv6Settings": MessageLookupByLibrary.simpleMessage("IPv6 settings"),
    "ipv6SettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Manage Mihomo IPv6 connectivity",
    ),
    "ja": MessageLookupByLibrary.simpleMessage("Japanese"),
    "justNow": MessageLookupByLibrary.simpleMessage("Just now"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "Tcp keep alive interval",
    ),
    "keptCount": MessageLookupByLibrary.simpleMessage("Kept"),
    "key": MessageLookupByLibrary.simpleMessage("Key"),
    "language": MessageLookupByLibrary.simpleMessage("Language"),
    "layout": MessageLookupByLibrary.simpleMessage("Layout"),
    "light": MessageLookupByLibrary.simpleMessage("Light"),
    "list": MessageLookupByLibrary.simpleMessage("List"),
    "listen": MessageLookupByLibrary.simpleMessage("Listen"),
    "liveConnectionList": MessageLookupByLibrary.simpleMessage(
      "Live connections",
    ),
    "liveConnectionsCount": m20,
    "liveConnectionsFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to load live connections. Try again later",
    ),
    "loadTest": MessageLookupByLibrary.simpleMessage("Load test"),
    "loading": MessageLookupByLibrary.simpleMessage("Loading..."),
    "loadingPaymentMethods": MessageLookupByLibrary.simpleMessage(
      "Loading payment methods…",
    ),
    "local": MessageLookupByLibrary.simpleMessage("Local"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Backup local data to local",
    ),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Location Permission",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Location permission was denied, so the current Wi-Fi name cannot be obtained. Please open location permission manually in system settings.",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "According to system requirements, obtaining the Wi-Fi name requires you to grant location permission.",
    ),
    "locationPermissionGuide": m21,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Location Permission Required",
    ),
    "log": MessageLookupByLibrary.simpleMessage("Log"),
    "logLevel": MessageLookupByLibrary.simpleMessage("LogLevel"),
    "logcat": MessageLookupByLibrary.simpleMessage("Logcat"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Disabling will hide the log entry",
    ),
    "loggedIn": MessageLookupByLibrary.simpleMessage("Signed in"),
    "loggingIn": MessageLookupByLibrary.simpleMessage("Logging in…"),
    "login": MessageLookupByLibrary.simpleMessage("Log in"),
    "loginEndpoint": MessageLookupByLibrary.simpleMessage("Login endpoint"),
    "loginEndpointLabel": m22,
    "loginFailed": MessageLookupByLibrary.simpleMessage(
      "Login failed. Please try again later",
    ),
    "loginSessionExpired": MessageLookupByLibrary.simpleMessage(
      "Your login session has expired. Please log in again",
    ),
    "loginWelcome": MessageLookupByLibrary.simpleMessage(
      "Welcome back, please log in to your account",
    ),
    "logoutAccount": MessageLookupByLibrary.simpleMessage("Log out"),
    "logoutConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "Saved sign-in information on this device will be cleared.",
    ),
    "logoutConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Sign out of this account?",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Logs"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("Log capture records"),
    "logsTest": MessageLookupByLibrary.simpleMessage("Logs test"),
    "loopback": MessageLookupByLibrary.simpleMessage("Loopback unlock tool"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage(
      "Used for UWP loopback unlocking",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Loose"),
    "lowestLatency": MessageLookupByLibrary.simpleMessage("Lowest latency"),
    "manageChainProxy": MessageLookupByLibrary.simpleMessage("Manage chain"),
    "manualSelection": MessageLookupByLibrary.simpleMessage("Manual select"),
    "matchContent": MessageLookupByLibrary.simpleMessage("Match content"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("Match source IP"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("Max failed times"),
    "memberValidUntil": MessageLookupByLibrary.simpleMessage(
      "Membership valid until",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Memory info"),
    "messageTest": MessageLookupByLibrary.simpleMessage("Message test"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage(
      "This is a message.",
    ),
    "min": MessageLookupByLibrary.simpleMessage("Min"),
    "mine": MessageLookupByLibrary.simpleMessage("My"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("Minimize on exit"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "Modify the default system exit event",
    ),
    "minutesAgo": m23,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Mixed Port"),
    "mixedPortSharedDescription": MessageLookupByLibrary.simpleMessage(
      "Shared HTTP & SOCKS5 port",
    ),
    "mode": MessageLookupByLibrary.simpleMessage("Mode"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Monochrome"),
    "monthlyBilling": MessageLookupByLibrary.simpleMessage("Monthly"),
    "monthsAgo": m24,
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "myInvitation": MessageLookupByLibrary.simpleMessage("My invitations"),
    "myOrders": MessageLookupByLibrary.simpleMessage("My orders"),
    "myWallet": MessageLookupByLibrary.simpleMessage("My wallet"),
    "name": MessageLookupByLibrary.simpleMessage("Name"),
    "nameserver": MessageLookupByLibrary.simpleMessage("Nameserver"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage(
      "For resolving domain",
    ),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage(
      "Nameserver policy",
    ),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "Specify the corresponding nameserver policy",
    ),
    "network": MessageLookupByLibrary.simpleMessage("Network"),
    "networkDesc": MessageLookupByLibrary.simpleMessage(
      "Modify network-related settings",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage(
      "Network detection",
    ),
    "networkDiagnosticConfigDnsFailed": MessageLookupByLibrary.simpleMessage(
      "The local proxy can access the internet, but no configuration domain resolves",
    ),
    "networkDiagnosticConfigDomains": MessageLookupByLibrary.simpleMessage(
      "Configuration domains",
    ),
    "networkDiagnosticConfigDomainsResult": m25,
    "networkDiagnosticCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "The proxy core is not running",
    ),
    "networkDiagnosticInternetFailed": MessageLookupByLibrary.simpleMessage(
      "Internet access through the local proxy failed",
    ),
    "networkDiagnosticInternetSuccess": MessageLookupByLibrary.simpleMessage(
      "Internet access through the local proxy succeeded",
    ),
    "networkDiagnosticLocalProxyPort": MessageLookupByLibrary.simpleMessage(
      "Local proxy port",
    ),
    "networkDiagnosticNoProfile": MessageLookupByLibrary.simpleMessage(
      "No subscription profile is available. Log in again or refresh the subscription",
    ),
    "networkDiagnosticNodeInternet": MessageLookupByLibrary.simpleMessage(
      "Node internet access",
    ),
    "networkDiagnosticNodeUnavailable": MessageLookupByLibrary.simpleMessage(
      "The local port works, but the current node cannot access the internet",
    ),
    "networkDiagnosticPortListening": m26,
    "networkDiagnosticPortNotListening": MessageLookupByLibrary.simpleMessage(
      "The core is running, but the local proxy port is not listening",
    ),
    "networkDiagnosticPortUnavailable": m27,
    "networkDiagnosticProxyFailure": m28,
    "networkDiagnosticProxyVerified": m29,
    "networkDiagnosticSuccess": MessageLookupByLibrary.simpleMessage(
      "Internet access through the local proxy succeeded; application and TUN traffic capture is not verified",
    ),
    "networkDiagnosticSystemProxyInvalid": MessageLookupByLibrary.simpleMessage(
      "The Windows system proxy is not configured correctly",
    ),
    "networkDiagnosticTrafficEntryMissing": MessageLookupByLibrary.simpleMessage(
      "The node works, but neither system proxy nor TUN is enabled, so application traffic will not enter the core",
    ),
    "networkDiagnosticWindowsSystemProxy": MessageLookupByLibrary.simpleMessage(
      "Windows system proxy",
    ),
    "networkException": MessageLookupByLibrary.simpleMessage(
      "Network exception, please check your connection and try again",
    ),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Network speed"),
    "networkType": MessageLookupByLibrary.simpleMessage("Network type"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Neutral"),
    "newPassword": MessageLookupByLibrary.simpleMessage("New password"),
    "nextAnnouncement": MessageLookupByLibrary.simpleMessage("Next"),
    "nextPage": MessageLookupByLibrary.simpleMessage("Next"),
    "nextPlanResetAt": m30,
    "noActiveConnections": MessageLookupByLibrary.simpleMessage(
      "No active connections. Start the VPN and browse to see them here",
    ),
    "noActivePlan": MessageLookupByLibrary.simpleMessage("No active plan"),
    "noAnnouncements": MessageLookupByLibrary.simpleMessage("No announcements"),
    "noChainProxy": MessageLookupByLibrary.simpleMessage("No chain proxies"),
    "noChainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "Add a SOCKS5 or HTTP proxy to get started.",
    ),
    "noCommissionRecords": MessageLookupByLibrary.simpleMessage(
      "No commission records",
    ),
    "noData": MessageLookupByLibrary.simpleMessage("No data"),
    "noHandlingFee": MessageLookupByLibrary.simpleMessage("No handling fee"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("No HotKey"),
    "noInfo": MessageLookupByLibrary.simpleMessage("No info"),
    "noInviteCodes": MessageLookupByLibrary.simpleMessage(
      "No invite codes yet. Generate one above.",
    ),
    "noLimit": MessageLookupByLibrary.simpleMessage("Unlimited"),
    "noLongerRemind": MessageLookupByLibrary.simpleMessage(
      "Don\'t remind again",
    ),
    "noMatchingConnections": MessageLookupByLibrary.simpleMessage(
      "No matching connections",
    ),
    "noNetwork": MessageLookupByLibrary.simpleMessage("No network"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("No network APP"),
    "noOrders": MessageLookupByLibrary.simpleMessage("No orders yet"),
    "noPaymentMethods": MessageLookupByLibrary.simpleMessage(
      "No payment method is currently available",
    ),
    "noPaymentRequired": MessageLookupByLibrary.simpleMessage(
      "No payment is required for this order",
    ),
    "noProfileForRule": MessageLookupByLibrary.simpleMessage(
      "There is no current profile where this rule can be saved",
    ),
    "noProxyGroupForFallback": MessageLookupByLibrary.simpleMessage(
      "This profile has no proxy group available for the global fallback rule",
    ),
    "noRecords": MessageLookupByLibrary.simpleMessage("No records"),
    "noResolve": MessageLookupByLibrary.simpleMessage("No resolve IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage(
      "No resolve hostname",
    ),
    "noTrafficRecords": MessageLookupByLibrary.simpleMessage(
      "No traffic records for this month",
    ),
    "nodeAvailable": MessageLookupByLibrary.simpleMessage("Available"),
    "nodeBackendOffline": MessageLookupByLibrary.simpleMessage(
      "Backend offline",
    ),
    "nodeBackendOnline": MessageLookupByLibrary.simpleMessage("Backend online"),
    "nodeLabel": MessageLookupByLibrary.simpleMessage("Node"),
    "nodeLocallyUnreachable": MessageLookupByLibrary.simpleMessage(
      "Unreachable here",
    ),
    "nodeNetworkFluctuating": MessageLookupByLibrary.simpleMessage(
      "Network unstable",
    ),
    "nodeStatus": MessageLookupByLibrary.simpleMessage("Nodes"),
    "nodeStatusSubtitle": MessageLookupByLibrary.simpleMessage(
      "Choose the best node for a fast and stable connection",
    ),
    "nodeStatusUnknown": MessageLookupByLibrary.simpleMessage("Status unknown"),
    "nodesCount": m31,
    "none": MessageLookupByLibrary.simpleMessage("none"),
    "notEnabled": MessageLookupByLibrary.simpleMessage("Not enabled"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "The current proxy group cannot be selected.",
    ),
    "notTested": MessageLookupByLibrary.simpleMessage("Not tested"),
    "notificationSettings": MessageLookupByLibrary.simpleMessage(
      "Notifications",
    ),
    "notificationSettingsSaved": MessageLookupByLibrary.simpleMessage(
      "Notification settings saved",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "No profile, Please add a profile",
    ),
    "nullTip": m32,
    "numberTip": m33,
    "offline": MessageLookupByLibrary.simpleMessage("Offline"),
    "offlineCacheContinues": MessageLookupByLibrary.simpleMessage(
      "Existing cache remains available on the dashboard and node pages.",
    ),
    "offlineCacheUnavailable": MessageLookupByLibrary.simpleMessage(
      "No valid subscription cache verified within the last three days",
    ),
    "offlineEntry": MessageLookupByLibrary.simpleMessage(
      "Continue with local cache",
    ),
    "offlineEntryHint": MessageLookupByLibrary.simpleMessage(
      "Use the most recently verified subscription and nodes",
    ),
    "offlineEntryUnavailable": MessageLookupByLibrary.simpleMessage(
      "No offline cache available",
    ),
    "offlineMode": MessageLookupByLibrary.simpleMessage("Offline mode"),
    "offlineModeBanner": MessageLookupByLibrary.simpleMessage(
      "Offline mode is enabled. Local cached data is being shown.",
    ),
    "offlineModeDescriptionTitle": MessageLookupByLibrary.simpleMessage(
      "About offline mode",
    ),
    "offlineModeEnabled": MessageLookupByLibrary.simpleMessage("Enabled"),
    "offlineNetworkTools": MessageLookupByLibrary.simpleMessage(
      "Network tools that do not require account sign-in remain available.",
    ),
    "offlineNoUpdates": MessageLookupByLibrary.simpleMessage(
      "Plans, invitations, subscriptions, and account data will not be refreshed.",
    ),
    "oldPassword": MessageLookupByLibrary.simpleMessage("Current password"),
    "onDemand": MessageLookupByLibrary.simpleMessage("On Demand"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "Configure the program running state for specific scenarios",
    ),
    "oneTimeBilling": MessageLookupByLibrary.simpleMessage("One-time"),
    "oneTimePlans": MessageLookupByLibrary.simpleMessage("One-time"),
    "online": MessageLookupByLibrary.simpleMessage("Online"),
    "onlineFeaturesUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "Restore online mode to use this feature",
    ),
    "onlineSupport": MessageLookupByLibrary.simpleMessage("Support"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("Icon"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Only statistics proxy",
    ),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "When turned on, only statistics proxy traffic",
    ),
    "optimizationComplete": MessageLookupByLibrary.simpleMessage(
      "Optimization complete",
    ),
    "optimizationDownload": MessageLookupByLibrary.simpleMessage(
      "Testing download speed",
    ),
    "optimizationFailed": MessageLookupByLibrary.simpleMessage(
      "No available Cloudflare IP was found. Check your connection and try again",
    ),
    "optimizationLatency": MessageLookupByLibrary.simpleMessage(
      "Testing connection latency",
    ),
    "optimizationPreparing": MessageLookupByLibrary.simpleMessage(
      "Loading Cloudflare candidate IPs",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("Optional"),
    "options": MessageLookupByLibrary.simpleMessage("Options"),
    "orderAmount": MessageLookupByLibrary.simpleMessage("Amount"),
    "orderCancelled": MessageLookupByLibrary.simpleMessage(
      "The order was cancelled",
    ),
    "orderCancelledSuccess": MessageLookupByLibrary.simpleMessage(
      "Order cancelled",
    ),
    "orderCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "Review plan and traffic-reset orders, payments, and activation status",
    ),
    "orderDetailsTitle": MessageLookupByLibrary.simpleMessage("Order details"),
    "orderListFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to load orders",
    ),
    "orderNumber": MessageLookupByLibrary.simpleMessage("Order number"),
    "orderPageIndicator": m34,
    "orderPeriod": MessageLookupByLibrary.simpleMessage("Period"),
    "orderPlan": MessageLookupByLibrary.simpleMessage("Plan"),
    "orderStatusCancelled": MessageLookupByLibrary.simpleMessage("Cancelled"),
    "orderStatusCompleted": MessageLookupByLibrary.simpleMessage("Completed"),
    "orderStatusPending": MessageLookupByLibrary.simpleMessage(
      "Pending payment",
    ),
    "orderStatusProcessing": MessageLookupByLibrary.simpleMessage("Activating"),
    "orderStatusUnknown": MessageLookupByLibrary.simpleMessage("Unknown"),
    "organization": MessageLookupByLibrary.simpleMessage("Organization"),
    "other": MessageLookupByLibrary.simpleMessage("Other"),
    "otherContributors": MessageLookupByLibrary.simpleMessage(
      "Other contributors",
    ),
    "otherTrafficPolicy": MessageLookupByLibrary.simpleMessage(
      "Other traffic policy",
    ),
    "outboundMode": MessageLookupByLibrary.simpleMessage("Outbound mode"),
    "override": MessageLookupByLibrary.simpleMessage("Override"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Override Dns"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "Turning it on will override the DNS options in the profile",
    ),
    "overrideMode": MessageLookupByLibrary.simpleMessage("Override mode"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("Override script"),
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("Custom"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "Custom mode, fully customize proxy groups and rules",
    ),
    "paidAt": MessageLookupByLibrary.simpleMessage("Paid at"),
    "palette": MessageLookupByLibrary.simpleMessage("Palette"),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordChanged": MessageLookupByLibrary.simpleMessage(
      "Password changed successfully",
    ),
    "passwordResetFailed": MessageLookupByLibrary.simpleMessage(
      "Password reset failed. Please try again later",
    ),
    "passwordResetSuccess": MessageLookupByLibrary.simpleMessage(
      "Password reset successfully. Log in with your new password",
    ),
    "passwordTooShort": MessageLookupByLibrary.simpleMessage(
      "Password must be at least 8 characters",
    ),
    "passwordsDoNotMatch": MessageLookupByLibrary.simpleMessage(
      "The passwords do not match",
    ),
    "paste": MessageLookupByLibrary.simpleMessage("Paste"),
    "paymentFailed": MessageLookupByLibrary.simpleMessage(
      "Payment not completed",
    ),
    "paymentMethod": MessageLookupByLibrary.simpleMessage("Payment method"),
    "paymentSecurityHint": MessageLookupByLibrary.simpleMessage(
      "Orders and QR codes are generated live by the XBoard payment API",
    ),
    "paymentStaysInApp": MessageLookupByLibrary.simpleMessage(
      "The payment QR code stays securely inside the app",
    ),
    "paymentSuccessful": MessageLookupByLibrary.simpleMessage(
      "Payment successful",
    ),
    "paymentSuccessfulHint": MessageLookupByLibrary.simpleMessage(
      "Your plan is being activated. Refresh the subscription shortly",
    ),
    "payoutTime": MessageLookupByLibrary.simpleMessage("Paid at"),
    "pendingCommission": MessageLookupByLibrary.simpleMessage(
      "Pending commission",
    ),
    "pendingTest": MessageLookupByLibrary.simpleMessage("Pending"),
    "peopleCount": m35,
    "personalCenter": MessageLookupByLibrary.simpleMessage("Account"),
    "planCatalogEmpty": MessageLookupByLibrary.simpleMessage(
      "No plans are available right now",
    ),
    "planCatalogFailed": MessageLookupByLibrary.simpleMessage(
      "Plans could not be loaded",
    ),
    "planDevicesLabel": MessageLookupByLibrary.simpleMessage("Devices"),
    "planSpeedLabel": MessageLookupByLibrary.simpleMessage("Speed"),
    "planStoreSubtitle": MessageLookupByLibrary.simpleMessage(
      "Secure global access with fast, stable connections",
    ),
    "planTrafficLabel": MessageLookupByLibrary.simpleMessage("Traffic"),
    "platformCount": MessageLookupByLibrary.simpleMessage("Platforms"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Please bind WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Please enter a script name",
    ),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "Please enter the admin password",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Please upload a valid QR code",
    ),
    "pleaseWait": MessageLookupByLibrary.simpleMessage(
      "Please wait and do not submit again",
    ),
    "popularApps": MessageLookupByLibrary.simpleMessage("Popular apps"),
    "popularAppsDescription": MessageLookupByLibrary.simpleMessage(
      "Browse useful clients and companion apps",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Port"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a different port",
    ),
    "portTip": m36,
    "practicalTools": MessageLookupByLibrary.simpleMessage("Utilities"),
    "practicalToolsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Everyday network tools for a faster, easier online experience",
    ),
    "preferH3Desc": MessageLookupByLibrary.simpleMessage(
      "Prioritize the use of DOH\'s http/3",
    ),
    "preferredNodes": MessageLookupByLibrary.simpleMessage("Preferred nodes"),
    "prerequisites": MessageLookupByLibrary.simpleMessage("Prerequisites"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Please press the keyboard.",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Preview"),
    "previousAnnouncement": MessageLookupByLibrary.simpleMessage("Previous"),
    "previousPage": MessageLookupByLibrary.simpleMessage("Previous"),
    "process": MessageLookupByLibrary.simpleMessage("Process"),
    "profile": MessageLookupByLibrary.simpleMessage("Profile"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Please input a valid interval time format",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Please enter the auto update interval time",
        ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "The profile has been modified. Do you want to disable auto update?",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please input the profile name",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please input a valid profile URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please input the profile URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Profiles"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Profiles sort"),
    "project": MessageLookupByLibrary.simpleMessage("Project"),
    "protocolLabel": MessageLookupByLibrary.simpleMessage("Protocol"),
    "providers": MessageLookupByLibrary.simpleMessage("Providers"),
    "provinceCity": MessageLookupByLibrary.simpleMessage("State/city"),
    "proxies": MessageLookupByLibrary.simpleMessage("Proxies"),
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("Proxies is empty"),
    "proxyAccessAddress": MessageLookupByLibrary.simpleMessage(
      "Local proxy address",
    ),
    "proxyChains": MessageLookupByLibrary.simpleMessage("Proxy chains"),
    "proxyDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "Detected selected proxies are abnormal",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("Proxy filter"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Proxy group"),
    "proxyGroupDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "Detected current proxy group is abnormal",
    ),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy group is empty",
    ),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "Proxy group name is duplicate",
    ),
    "proxyGroupNameEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy group name cannot be empty",
    ),
    "proxyNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "This proxy name already exists",
    ),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("Proxy nameserver"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Domain for resolving proxy nodes",
    ),
    "proxyNeededChooseNode": MessageLookupByLibrary.simpleMessage(
      "Need a proxy: open the node list and choose a non-DIRECT node.",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("ProxyPort"),
    "proxyProtocolMismatch": MessageLookupByLibrary.simpleMessage(
      "Incorrect protocol. Detected protocol:",
    ),
    "proxyProviderDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "Detected selected proxy providers are abnormal",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Proxy providers"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy providers is empty",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy providers cannot be empty",
    ),
    "proxyServer": MessageLookupByLibrary.simpleMessage("Server"),
    "proxySettings": MessageLookupByLibrary.simpleMessage("Proxy settings"),
    "proxySettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Manage the local proxy service",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("Proxy type"),
    "proxyValidationFailed": MessageLookupByLibrary.simpleMessage(
      "Cannot connect through this proxy. Check the server, port, username, and password",
    ),
    "pruneCache": MessageLookupByLibrary.simpleMessage("Prune cache"),
    "publicIp": MessageLookupByLibrary.simpleMessage("Public IP"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("Plans"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Pure black mode"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR code"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Scan QR code to obtain profile",
    ),
    "qualityNodes": MessageLookupByLibrary.simpleMessage("Quality nodes"),
    "quarterlyBilling": MessageLookupByLibrary.simpleMessage("Quarterly"),
    "queryNow": MessageLookupByLibrary.simpleMessage("Check now"),
    "quickFill": MessageLookupByLibrary.simpleMessage("Quick fill"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Rainbow"),
    "reachable": MessageLookupByLibrary.simpleMessage("Reachable"),
    "realTimeConnections": MessageLookupByLibrary.simpleMessage(
      "Live connections",
    ),
    "realTimeConnectionsSubtitle": MessageLookupByLibrary.simpleMessage(
      "VPN acceleration is active and protecting your network connections",
    ),
    "recurringPlans": MessageLookupByLibrary.simpleMessage("Recurring"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir Port"),
    "redo": MessageLookupByLibrary.simpleMessage("redo"),
    "refreshApiStatus": MessageLookupByLibrary.simpleMessage(
      "Refresh API status",
    ),
    "refreshConfiguration": MessageLookupByLibrary.simpleMessage(
      "Refresh config",
    ),
    "refreshData": MessageLookupByLibrary.simpleMessage("Refresh data"),
    "refreshNodes": MessageLookupByLibrary.simpleMessage("Refresh"),
    "refreshSubscription": MessageLookupByLibrary.simpleMessage(
      "Refresh subscription",
    ),
    "region": MessageLookupByLibrary.simpleMessage("Region"),
    "registerAccount": MessageLookupByLibrary.simpleMessage("Create account"),
    "registerAction": MessageLookupByLibrary.simpleMessage("Register"),
    "registeredUsers": MessageLookupByLibrary.simpleMessage("Registered users"),
    "registrationApiPending": MessageLookupByLibrary.simpleMessage(
      "Registration API is not connected yet",
    ),
    "registrationFailed": MessageLookupByLibrary.simpleMessage(
      "Registration failed. Please try again later",
    ),
    "registrationSuccess": MessageLookupByLibrary.simpleMessage(
      "Registration successful",
    ),
    "reject": MessageLookupByLibrary.simpleMessage("Reject"),
    "remainingCommission": MessageLookupByLibrary.simpleMessage(
      "Available commission",
    ),
    "remainingTraffic": MessageLookupByLibrary.simpleMessage(
      "Remaining traffic",
    ),
    "remainingTrafficLabel": MessageLookupByLibrary.simpleMessage("Remaining"),
    "rememberMe": MessageLookupByLibrary.simpleMessage("Remember me"),
    "rememberedLoginHint": MessageLookupByLibrary.simpleMessage(
      "Account remembered — click Log in",
    ),
    "rememberedLoginSaveFailed": MessageLookupByLibrary.simpleMessage(
      "Login succeeded, but your credentials could not be saved securely. You will need your password next time.",
    ),
    "rememberedPassword": MessageLookupByLibrary.simpleMessage(
      "Remembered your password?",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("Remote"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Backup local data to WebDAV",
    ),
    "remoteDestination": MessageLookupByLibrary.simpleMessage(
      "Remote destination",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Remove"),
    "rename": MessageLookupByLibrary.simpleMessage("Rename"),
    "renewPlanAction": MessageLookupByLibrary.simpleMessage("Renew"),
    "renewalDoesNotResetTraffic": MessageLookupByLibrary.simpleMessage(
      "A renewal order only extends the plan expiry date and does not reset used traffic. Choose Reset traffic if you need to restore the plan quota.",
    ),
    "renewalNoticeTitle": MessageLookupByLibrary.simpleMessage(
      "Renewal notice",
    ),
    "renewalUnavailable": MessageLookupByLibrary.simpleMessage(
      "This plan does not currently support renewal",
    ),
    "request": MessageLookupByLibrary.simpleMessage("Request"),
    "requestFailed": MessageLookupByLibrary.simpleMessage(
      "Request failed. Please try again later",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("Requests"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage(
      "View recently request records",
    ),
    "requiredField": MessageLookupByLibrary.simpleMessage(
      "This field is required",
    ),
    "rerunOptimization": MessageLookupByLibrary.simpleMessage("Scan again"),
    "reset": MessageLookupByLibrary.simpleMessage("Reset"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "The current page has changes. Are you sure you want to reset?",
    ),
    "resetPasswordAction": MessageLookupByLibrary.simpleMessage(
      "Reset password",
    ),
    "resetSubscription": MessageLookupByLibrary.simpleMessage(
      "Reset subscription",
    ),
    "resetSubscriptionConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "The old address will stop working immediately and every device must sync again.",
    ),
    "resetSubscriptionConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Reset the subscription?",
    ),
    "resetSubscriptionDescription": MessageLookupByLibrary.simpleMessage(
      "Generate a new subscription address if the current one is exposed or unavailable",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("Make sure to reset"),
    "resetTrafficAction": MessageLookupByLibrary.simpleMessage("Reset traffic"),
    "resettingPassword": MessageLookupByLibrary.simpleMessage("Resetting…"),
    "resources": MessageLookupByLibrary.simpleMessage("Resources"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage(
      "External resource related info",
    ),
    "respectRules": MessageLookupByLibrary.simpleMessage("Respect rules"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS connection following rules, need to configure proxy-server-nameserver",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("Restart"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to restart the core?",
    ),
    "restore": MessageLookupByLibrary.simpleMessage("Restore"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("Restore all data"),
    "restoreException": MessageLookupByLibrary.simpleMessage(
      "Recovery exception",
    ),
    "restoreFromFileDesc": MessageLookupByLibrary.simpleMessage(
      "Restore data via file",
    ),
    "restoreFromWebDAVDesc": MessageLookupByLibrary.simpleMessage(
      "Restore data via WebDAV",
    ),
    "restoreOnline": MessageLookupByLibrary.simpleMessage(
      "Restore online mode",
    ),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage(
      "Restore configuration files only",
    ),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("Restore strategy"),
    "restoreStrategy_compatible": MessageLookupByLibrary.simpleMessage(
      "Compatible",
    ),
    "restoreStrategy_override": MessageLookupByLibrary.simpleMessage(
      "Override",
    ),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage("Restore success"),
    "restoringOnline": MessageLookupByLibrary.simpleMessage(
      "Restoring online mode…",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Retry"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Route address"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage(
      "Config listen route address",
    ),
    "routeMode": MessageLookupByLibrary.simpleMessage("Route mode"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Bypass private route address",
    ),
    "routeMode_config": MessageLookupByLibrary.simpleMessage("Use config"),
    "ru": MessageLookupByLibrary.simpleMessage("Russian"),
    "rule": MessageLookupByLibrary.simpleMessage("Rule"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage(
      "Logical rule AND",
    ),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Match full domain",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "Match domain keyword",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Wildcard match, only supports * and ? wildcards",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match domain suffix",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "Match DSCP mark (tproxy udp inbound only)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match request target port range",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Match IP\'s country code",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Match domains within Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match inbound name",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match inbound port",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "Match inbound type",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "Match inbound username, supports multiple usernames separated by /",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Match IP\'s ASN",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "Match IP address range, IP-CIDR6 is just an alias",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Match IP address range",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match IP suffix range",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "Match all requests, no conditions needed",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "Match TCP or UDP",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage(
      "Logical rule NOT",
    ),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("Logical rule OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match using process name, matches package name on Android",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match using process name regex, matches package name on Android",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "Match using full process path",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match using process path regex",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "Reference rule set, requires rule-providers configuration",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Match source IP\'s country code",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Match source IP\'s ASN",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Match source IP address range",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match source IP suffix range",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match request source port range",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "Match to sub-rule, pay attention to the use of parentheses",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Match Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("Rule is empty"),
    "ruleName": MessageLookupByLibrary.simpleMessage("Rule name"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Rule providers"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("Rule set"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Rule target"),
    "ruleType": MessageLookupByLibrary.simpleMessage("Rule type"),
    "ruleTypeHelp": MessageLookupByLibrary.simpleMessage(
      "DOMAIN matches the exact domain; DOMAIN-SUFFIX also matches subdomains",
    ),
    "runNetworkDiagnostics": MessageLookupByLibrary.simpleMessage(
      "Run network diagnostics",
    ),
    "save": MessageLookupByLibrary.simpleMessage("Save"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Save changes"),
    "savedDnsServersCount": m37,
    "scanToPay": MessageLookupByLibrary.simpleMessage("Scan to pay"),
    "scanWithPaymentApp": MessageLookupByLibrary.simpleMessage(
      "Scan the QR code below with the matching payment app",
    ),
    "script": MessageLookupByLibrary.simpleMessage("Script"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "Script mode, use external extension scripts, provide one-click override configuration capability",
    ),
    "search": MessageLookupByLibrary.simpleMessage("Search"),
    "searchConnectionsHint": MessageLookupByLibrary.simpleMessage(
      "Search domain, IP, rule, or node",
    ),
    "seconds": MessageLookupByLibrary.simpleMessage("Seconds"),
    "secondsCount": m38,
    "selectAll": MessageLookupByLibrary.simpleMessage("Select all"),
    "selectPaymentMethod": MessageLookupByLibrary.simpleMessage(
      "Select a payment method",
    ),
    "selectProxies": MessageLookupByLibrary.simpleMessage("Select proxies"),
    "selectProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Select a proxy group",
    ),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Select proxy providers",
    ),
    "selectRenewalPeriod": MessageLookupByLibrary.simpleMessage(
      "Select a renewal period",
    ),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage(
      "Please select rule set",
    ),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "Please select split strategy",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage(
      "Please select sub rule",
    ),
    "selectWithdrawalMethod": MessageLookupByLibrary.simpleMessage(
      "Select a withdrawal method",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("Selected"),
    "selectedCountTitle": m39,
    "sendVerificationCode": MessageLookupByLibrary.simpleMessage("Send"),
    "sendingVerificationCode": MessageLookupByLibrary.simpleMessage(
      "Sending...",
    ),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("Service status"),
    "settings": MessageLookupByLibrary.simpleMessage("Settings"),
    "show": MessageLookupByLibrary.simpleMessage("Show"),
    "showPassword": MessageLookupByLibrary.simpleMessage("Show password"),
    "shrink": MessageLookupByLibrary.simpleMessage("Shrink"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("SilentLaunch"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Start in the background",
    ),
    "size": MessageLookupByLibrary.simpleMessage("Size"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks Port"),
    "soldOut": MessageLookupByLibrary.simpleMessage("Sold out"),
    "sort": MessageLookupByLibrary.simpleMessage("Sort"),
    "source": MessageLookupByLibrary.simpleMessage("Source"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("Source IP"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("Special proxy"),
    "specialRules": MessageLookupByLibrary.simpleMessage("special rules"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("Speed statistics"),
    "speedTest": MessageLookupByLibrary.simpleMessage("Speed test"),
    "speedTestDescription": MessageLookupByLibrary.simpleMessage(
      "Test your current connection with a third-party speed service",
    ),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("Split strategy"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Split strategy cannot be empty",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs is empty"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Stack mode"),
    "standard": MessageLookupByLibrary.simpleMessage("Standard"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "Standard mode, override basic configuration, provide simple rule addition capability",
    ),
    "standardizedDelay": MessageLookupByLibrary.simpleMessage("Standard RTT"),
    "start": MessageLookupByLibrary.simpleMessage("Start"),
    "startAcceleration": MessageLookupByLibrary.simpleMessage(
      "Start acceleration",
    ),
    "startOptimization": MessageLookupByLibrary.simpleMessage("Start scan"),
    "startTest": MessageLookupByLibrary.simpleMessage("Start test"),
    "startVpn": MessageLookupByLibrary.simpleMessage("Starting VPN..."),
    "status": MessageLookupByLibrary.simpleMessage("Status"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "System DNS will be used when turned off",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Stop"),
    "stopAcceleration": MessageLookupByLibrary.simpleMessage(
      "Stop acceleration",
    ),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Stopping VPN..."),
    "streamingExitRegion": MessageLookupByLibrary.simpleMessage("Exit region"),
    "streamingFailed": MessageLookupByLibrary.simpleMessage(
      "Connection failed",
    ),
    "streamingNetworkError": MessageLookupByLibrary.simpleMessage(
      "Network connection failed",
    ),
    "streamingProxyRequired": MessageLookupByLibrary.simpleMessage(
      "Start acceleration and select a proxy node before testing",
    ),
    "streamingReachable": MessageLookupByLibrary.simpleMessage(
      "Web page reachable, deep status unconfirmed",
    ),
    "streamingReachableProbeFailed": MessageLookupByLibrary.simpleMessage(
      "Web page reachable, deep status unconfirmed",
    ),
    "streamingReachableProbeTimedOut": MessageLookupByLibrary.simpleMessage(
      "Web page reachable, deep check timed out",
    ),
    "streamingRestricted": MessageLookupByLibrary.simpleMessage(
      "Region restricted",
    ),
    "streamingServiceError": MessageLookupByLibrary.simpleMessage(
      "Service is temporarily unavailable",
    ),
    "streamingTimedOut": MessageLookupByLibrary.simpleMessage(
      "Test timed out. Try again",
    ),
    "streamingUnlockTest": MessageLookupByLibrary.simpleMessage(
      "Streaming access test",
    ),
    "streamingUnlockTestDescription": MessageLookupByLibrary.simpleMessage(
      "Check streaming and AI service availability on this node",
    ),
    "streamingUnlocked": MessageLookupByLibrary.simpleMessage(
      "Web page reachable",
    ),
    "style": MessageLookupByLibrary.simpleMessage("Style"),
    "subRule": MessageLookupByLibrary.simpleMessage("Sub rule"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("Sub rule is empty"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Sub rule cannot be empty",
    ),
    "submit": MessageLookupByLibrary.simpleMessage("Submit"),
    "submitWithdrawalTicket": MessageLookupByLibrary.simpleMessage(
      "Submit withdrawal ticket",
    ),
    "subscriptionExpiredWarning": m40,
    "subscriptionExpiringWarning": m41,
    "subscriptionImportFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to load subscription nodes. Check your network and try again",
    ),
    "subscriptionLowTrafficWarning": m42,
    "subscriptionNormalTooltip": MessageLookupByLibrary.simpleMessage(
      "Plan status is normal. Click to view details",
    ),
    "subscriptionPlanUnavailable": MessageLookupByLibrary.simpleMessage(
      "The current plan could not be found. Refresh and try again",
    ),
    "subscriptionResetSuccess": MessageLookupByLibrary.simpleMessage(
      "Subscription reset and synchronized",
    ),
    "subscriptionStatusNormalMessage": MessageLookupByLibrary.simpleMessage(
      "Your remaining traffic and plan validity are both in a normal state.",
    ),
    "subscriptionStatusNormalTitle": MessageLookupByLibrary.simpleMessage(
      "Plan status normal",
    ),
    "subscriptionWarningTitle": MessageLookupByLibrary.simpleMessage(
      "Plan warning",
    ),
    "subscriptionWarningTooltip": MessageLookupByLibrary.simpleMessage(
      "Plan warning. Click to view details",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("Suspended..."),
    "switchAndDirect": MessageLookupByLibrary.simpleMessage(
      "Switch and use DIRECT",
    ),
    "switchNode": MessageLookupByLibrary.simpleMessage("Switch node"),
    "switchToGlobalMode": MessageLookupByLibrary.simpleMessage(
      "Switch to global mode",
    ),
    "sync": MessageLookupByLibrary.simpleMessage("Sync"),
    "system": MessageLookupByLibrary.simpleMessage("System"),
    "systemApp": MessageLookupByLibrary.simpleMessage("System APP"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "systemProxyApplyFailed": m43,
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Attach HTTP proxy to VpnService",
    ),
    "systemProxyDisableFailed": m44,
    "systemProxyStaleCleaned": MessageLookupByLibrary.simpleMessage(
      "The system proxy left by the previous abnormal exit was cleared",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("Tab"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Tab animation"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Effective only in mobile view",
    ),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("Tap to authorize"),
    "targetPolicy": MessageLookupByLibrary.simpleMessage("Target policy"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP concurrent"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage(
      "Enabling it will allow TCP concurrency",
    ),
    "telegramBinding": MessageLookupByLibrary.simpleMessage("Telegram binding"),
    "telegramId": MessageLookupByLibrary.simpleMessage("Telegram ID"),
    "telegramUnboundHint": MessageLookupByLibrary.simpleMessage(
      "Telegram is not bound to this account",
    ),
    "testAll": MessageLookupByLibrary.simpleMessage("Test all"),
    "testAllEndpoints": MessageLookupByLibrary.simpleMessage("Test all"),
    "testEndpoint": MessageLookupByLibrary.simpleMessage("Test"),
    "testInterval": MessageLookupByLibrary.simpleMessage("Test interval"),
    "testUrl": MessageLookupByLibrary.simpleMessage("Test url"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("Test when used"),
    "testingStatus": MessageLookupByLibrary.simpleMessage("Testing"),
    "textScale": MessageLookupByLibrary.simpleMessage("Text Scaling"),
    "theme": MessageLookupByLibrary.simpleMessage("Theme"),
    "themeColor": MessageLookupByLibrary.simpleMessage("Theme color"),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Set dark mode,adjust the color",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Theme mode"),
    "threeYearBilling": MessageLookupByLibrary.simpleMessage("3 years"),
    "tight": MessageLookupByLibrary.simpleMessage("Tight"),
    "time": MessageLookupByLibrary.simpleMessage("Time"),
    "timeout": MessageLookupByLibrary.simpleMessage("Timeout"),
    "timezoneLabel": MessageLookupByLibrary.simpleMessage("Time zone"),
    "tip": MessageLookupByLibrary.simpleMessage("tip"),
    "todayTraffic": MessageLookupByLibrary.simpleMessage("Today"),
    "toggle": MessageLookupByLibrary.simpleMessage("Toggle"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("TonalSpot"),
    "toolbox": MessageLookupByLibrary.simpleMessage("Toolbox"),
    "tools": MessageLookupByLibrary.simpleMessage("Tools"),
    "totalCommission": MessageLookupByLibrary.simpleMessage("Total commission"),
    "totalOrders": m45,
    "totalTrafficLabel": MessageLookupByLibrary.simpleMessage("Total"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy Port"),
    "trafficDetailRecords": MessageLookupByLibrary.simpleMessage(
      "Traffic usage records",
    ),
    "trafficDetails": MessageLookupByLibrary.simpleMessage("Traffic"),
    "trafficDetailsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Review usage and understand your network trends",
    ),
    "trafficEmailReminder": MessageLookupByLibrary.simpleMessage(
      "Traffic email reminder",
    ),
    "trafficRate": MessageLookupByLibrary.simpleMessage("Rate"),
    "trafficRecordsFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to load traffic data",
    ),
    "trafficResetBilling": MessageLookupByLibrary.simpleMessage("Reset"),
    "trafficResetUnavailable": MessageLookupByLibrary.simpleMessage(
      "This plan does not currently support traffic reset",
    ),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("Traffic usage"),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "only effective in administrator mode",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("Turn Off"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Turn On"),
    "twoYearBilling": MessageLookupByLibrary.simpleMessage("2 years"),
    "unbound": MessageLookupByLibrary.simpleMessage("Not bound"),
    "undo": MessageLookupByLibrary.simpleMessage("undo"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("Unified delay"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "Remove extra delays such as handshaking",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("Unknown"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage(
      "Unknown network error",
    ),
    "unlimitedTime": MessageLookupByLibrary.simpleMessage("Unlimited"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Unnamed"),
    "unreachable": MessageLookupByLibrary.simpleMessage("Unreachable"),
    "update": MessageLookupByLibrary.simpleMessage("Update"),
    "updateAll": MessageLookupByLibrary.simpleMessage("Update all"),
    "upgradePlanAction": MessageLookupByLibrary.simpleMessage("Upgrade"),
    "upload": MessageLookupByLibrary.simpleMessage("Upload"),
    "uploadSpeed": MessageLookupByLibrary.simpleMessage("Upload speed"),
    "uploadTraffic": MessageLookupByLibrary.simpleMessage("Upload"),
    "uploaded": MessageLookupByLibrary.simpleMessage("Uploaded"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage(
      "Obtain profile through URL",
    ),
    "urlTip": m46,
    "useHosts": MessageLookupByLibrary.simpleMessage("Use hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("Use system hosts"),
    "usedTrafficLabel": MessageLookupByLibrary.simpleMessage("Used"),
    "userAgent": MessageLookupByLibrary.simpleMessage("User-Agent"),
    "userInfoFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to load account information",
    ),
    "userMapLabel": MessageLookupByLibrary.simpleMessage("User"),
    "username": MessageLookupByLibrary.simpleMessage("Username"),
    "validatingProxy": MessageLookupByLibrary.simpleMessage(
      "Validating proxy connection…",
    ),
    "validatingTargets": MessageLookupByLibrary.simpleMessage(
      "Validating target domains against preferred IPs",
    ),
    "value": MessageLookupByLibrary.simpleMessage("Value"),
    "verificationApiPending": MessageLookupByLibrary.simpleMessage(
      "Verification API is not connected yet",
    ),
    "verificationEmailSent": MessageLookupByLibrary.simpleMessage(
      "Verification code sent. Check your spam folder if it does not arrive",
    ),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Vibrant"),
    "view": MessageLookupByLibrary.simpleMessage("View"),
    "viewApps": MessageLookupByLibrary.simpleMessage("View apps"),
    "viewDetails": MessageLookupByLibrary.simpleMessage("View details"),
    "viewOrderDetails": MessageLookupByLibrary.simpleMessage("View details"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "VPN configuration change detected",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "Auto routes all system traffic through VpnService",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Changes take effect after restarting the VPN",
    ),
    "waitingForPayment": MessageLookupByLibrary.simpleMessage(
      "Waiting for payment",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "WebDAV configuration",
    ),
    "whatHappensAfterSwitch": MessageLookupByLibrary.simpleMessage(
      "What happens after switching",
    ),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("Whitelist mode"),
    "withdrawalAccount": MessageLookupByLibrary.simpleMessage(
      "Receiving account",
    ),
    "withdrawalAmount": MessageLookupByLibrary.simpleMessage(
      "Withdrawal amount",
    ),
    "withdrawalAmountExceeds": MessageLookupByLibrary.simpleMessage(
      "The amount cannot exceed available commission",
    ),
    "withdrawalAmountInvalid": MessageLookupByLibrary.simpleMessage(
      "Enter a valid withdrawal amount",
    ),
    "withdrawalMethod": MessageLookupByLibrary.simpleMessage(
      "Withdrawal method",
    ),
    "withdrawalMethodAlipay": MessageLookupByLibrary.simpleMessage("Alipay"),
    "withdrawalMethodBank": MessageLookupByLibrary.simpleMessage("Bank card"),
    "withdrawalMethodUsdt": MessageLookupByLibrary.simpleMessage("USDT"),
    "withdrawalMethodWechat": MessageLookupByLibrary.simpleMessage(
      "WeChat Pay",
    ),
    "withdrawalRequestTitle": MessageLookupByLibrary.simpleMessage(
      "Commission withdrawal request",
    ),
    "withdrawalTicketCreated": MessageLookupByLibrary.simpleMessage(
      "Withdrawal ticket submitted. Please wait for an administrator to process it.",
    ),
    "withdrawalTicketDescription": MessageLookupByLibrary.simpleMessage(
      "A support ticket will be created in the system for an administrator to process.",
    ),
    "yearlyBilling": MessageLookupByLibrary.simpleMessage("Yearly"),
    "yearsAgo": m47,
    "zh_CN": MessageLookupByLibrary.simpleMessage("Simplified Chinese"),
    "zoomIn": MessageLookupByLibrary.simpleMessage("Zoom in"),
    "zoomOut": MessageLookupByLibrary.simpleMessage("Zoom out"),
  };
}
