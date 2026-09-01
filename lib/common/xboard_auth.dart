import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_endpoint_preference.dart';
import 'api_health.dart';
import 'subscription_v2.dart';

const xboardLoginPath = '/api/v1/passport/auth/login';
const xboardSubscribePath = '/api/v1/user/getSubscribe';
const xboardServerFetchPath = '/api/v1/user/server/fetch';
const xboardPlanFetchPath = '/api/v1/user/plan/fetch';
const xboardOrderSavePath = '/api/v1/user/order/save';
const xboardPaymentMethodPath = '/api/v1/user/order/getPaymentMethod';
const xboardOrderCheckoutPath = '/api/v1/user/order/checkout';
const xboardOrderCheckPath = '/api/v1/user/order/check';
const xboardOrderFetchPath = '/api/v1/user/order/fetch';
const xboardOrderDetailPath = '/api/v1/user/order/detail';
const xboardOrderCancelPath = '/api/v1/user/order/cancel';
const xboardNoticeFetchPath = '/api/v1/user/notice/fetch';
const xboardUserInfoPath = '/api/v1/user/info';
const xboardUserUpdatePath = '/api/v1/user/update';
const xboardChangePasswordPath = '/api/v1/user/changePassword';
const xboardResetSecurityPath = '/api/v1/user/resetSecurity';
const xboardTrafficLogPath = '/api/v1/user/stat/getTrafficLog';
const xboardInviteFetchPath = '/api/v1/user/invite/fetch';
const xboardInviteSavePath = '/api/v1/user/invite/save';
const xboardInviteDetailsPath = '/api/v1/user/invite/details';
const xboardCommissionTransferPath = '/api/v1/user/transfer';
const xboardTicketSavePath = '/api/v1/user/ticket/save';
const xboardGuestConfigPath = '/api/v1/guest/comm/config';
const xboardSendEmailVerifyPath = '/api/v1/passport/comm/sendEmailVerify';
const xboardRegisterPath = '/api/v1/passport/auth/register';
const xboardForgetPasswordPath = '/api/v1/passport/auth/forget';
const bytesPerGigabyte = 1024 * 1024 * 1024;
double bytesToGigabytes(num bytes) => bytes / bytesPerGigabyte;

enum XboardAuthFailure {
  noAvailableHost,
  authenticationRejected,
  rateLimited,
  subscriptionRejected,
  subscriptionUnavailable,
  verificationRejected,
  registrationRejected,
  passwordResetRejected,
  invalidResponse,
  unavailable,
}

class XboardAuthException implements Exception {
  const XboardAuthException({
    required this.failure,
    required this.message,
    this.statusCode,
    this.endpoint,
  });

  final XboardAuthFailure failure;
  final String message;
  final int? statusCode;
  final Uri? endpoint;

  @override
  String toString() => 'XboardAuthException($failure, $statusCode)';
}

class XboardLoginResult {
  const XboardLoginResult({
    required this.endpoint,
    required this.token,
    required this.authData,
    required this.isAdmin,
    required this.subscription,
    this.secureSubscription = false,
    this.rawData = const {},
  });

  final Uri endpoint;
  final String token;
  final String authData;
  final bool isAdmin;
  final XboardSubscriptionData subscription;
  final bool secureSubscription;
  final Map<String, Object?> rawData;

  Uri? get subscribeUrl => subscription.subscribeUrl;
}

class XboardSubscriptionData {
  const XboardSubscriptionData({
    required this.endpoint,
    required this.subscribeUrl,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.transferEnableBytes,
    required this.rawData,
    this.planId,
    this.token,
    this.email,
    this.uuid,
    this.expiredAtEpochSeconds,
    this.deviceLimit,
    this.speedLimit,
    this.nextResetAtEpochSeconds,
    this.resetDay,
    this.plan,
  });

  final Uri endpoint;
  final Uri? subscribeUrl;
  final int uploadBytes;
  final int downloadBytes;
  final int transferEnableBytes;
  final int? planId;
  final String? token;
  final String? email;
  final String? uuid;
  final int? expiredAtEpochSeconds;
  final int? deviceLimit;
  final int? speedLimit;
  final int? nextResetAtEpochSeconds;
  final int? resetDay;
  final XboardPlanData? plan;
  final Map<String, Object?> rawData;

  int get usedBytes => uploadBytes + downloadBytes;

  int get remainingBytes =>
      (transferEnableBytes - usedBytes).clamp(0, transferEnableBytes);

  double get uploadGb => bytesToGigabytes(uploadBytes);

  double get downloadGb => bytesToGigabytes(downloadBytes);

  double get usedGb => bytesToGigabytes(usedBytes);

  double get remainingGb => bytesToGigabytes(remainingBytes);

  double get transferEnableGb => bytesToGigabytes(transferEnableBytes);

  bool get isUnlimitedTime => expiredAtEpochSeconds == null;

  bool get isMonthlyPlan => expiredAtEpochSeconds != null;

  DateTime? get expiresAt => expiredAtEpochSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          expiredAtEpochSeconds! * 1000,
          isUtc: true,
        ).toLocal();

  DateTime? get nextResetAt =>
      nextResetAtEpochSeconds == null || nextResetAtEpochSeconds! <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          nextResetAtEpochSeconds! * 1000,
          isUtc: true,
        ).toLocal();

  bool get shouldShowNextPlanReset => nextResetAt != null && isMonthlyPlan;

  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;
}

class XboardPlanData {
  const XboardPlanData({
    required this.rawData,
    this.id,
    this.name,
    this.transferEnableBytes,
  });

  final int? id;
  final String? name;
  final int? transferEnableBytes;
  final Map<String, Object?> rawData;

  double? get transferEnableGb => transferEnableBytes == null
      ? null
      : bytesToGigabytes(transferEnableBytes!);
}

class XboardNodeData {
  const XboardNodeData({
    required this.name,
    required this.type,
    required this.rate,
    required this.tags,
    required this.isOnline,
    required this.rawData,
    this.id,
  });

  final int? id;
  final String name;
  final String type;
  final double rate;
  final List<String> tags;
  final bool isOnline;
  final Map<String, Object?> rawData;
}

class XboardTrafficLog {
  const XboardTrafficLog({
    required this.downloadBytes,
    required this.uploadBytes,
    required this.recordAtEpochSeconds,
    required this.serverRate,
    required this.rawData,
  });

  final int downloadBytes;
  final int uploadBytes;
  final int recordAtEpochSeconds;
  final double serverRate;
  final Map<String, Object?> rawData;

  int get rawBytes => downloadBytes + uploadBytes;

  double get billedBytes => rawBytes * serverRate;

  DateTime get recordedAt => DateTime.fromMillisecondsSinceEpoch(
    recordAtEpochSeconds * 1000,
    isUtc: true,
  ).toLocal();
}

class XboardNoticeData {
  const XboardNoticeData({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    required this.createdAtEpochSeconds,
    required this.updatedAtEpochSeconds,
    required this.rawData,
    this.imageUrl,
  });

  final int id;
  final String title;
  final String content;
  final List<String> tags;
  final int? createdAtEpochSeconds;
  final int? updatedAtEpochSeconds;
  final Uri? imageUrl;
  final Map<String, Object?> rawData;

  bool get isPopup => tags.any((tag) => tag.trim() == '弹窗');

  DateTime? get createdAt => createdAtEpochSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          createdAtEpochSeconds! * 1000,
          isUtc: true,
        ).toLocal();
}

class XboardAvailablePlan {
  const XboardAvailablePlan({
    required this.id,
    required this.name,
    required this.tags,
    required this.content,
    required this.transferEnableGb,
    required this.speedLimit,
    required this.deviceLimit,
    required this.prices,
    required this.sell,
    required this.renew,
    required this.isSoldOut,
    required this.rawData,
  });

  final int id;
  final String name;
  final List<String> tags;
  final String content;
  final double transferEnableGb;
  final int? speedLimit;
  final int? deviceLimit;
  final Map<String, int> prices;
  final bool sell;
  final bool renew;
  final bool isSoldOut;
  final Map<String, Object?> rawData;
}

class XboardPaymentMethod {
  const XboardPaymentMethod({
    required this.id,
    required this.name,
    required this.payment,
    required this.handlingFeeFixed,
    required this.handlingFeePercent,
    required this.rawData,
    this.icon,
  });

  final int id;
  final String name;
  final String payment;
  final String? icon;
  final int handlingFeeFixed;
  final double handlingFeePercent;
  final Map<String, Object?> rawData;
}

class XboardCheckoutResult {
  const XboardCheckoutResult({
    required this.type,
    required this.data,
    required this.rawData,
  });

  final int type;
  final Object? data;
  final Map<String, Object?> rawData;

  bool get isFree => type == -1;

  String? get paymentPayload {
    final value = data;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Map) {
      const keys = ['qrcode', 'qr_code', 'url', 'pay_url', 'payment_url'];
      for (final key in keys) {
        final candidate = value[key]?.toString().trim();
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }
    }
    return null;
  }
}

class XboardOrderData {
  const XboardOrderData({
    required this.id,
    required this.tradeNo,
    required this.period,
    required this.totalAmount,
    required this.status,
    required this.createdAtEpochSeconds,
    required this.rawData,
    this.planName,
    this.paymentName,
    this.paidAtEpochSeconds,
    this.handlingAmount = 0,
    this.discountAmount = 0,
    this.balanceAmount = 0,
  });

  final int id;
  final String tradeNo;
  final String period;
  final int totalAmount;
  final int status;
  final int createdAtEpochSeconds;
  final String? planName;
  final String? paymentName;
  final int? paidAtEpochSeconds;
  final int handlingAmount;
  final int discountAmount;
  final int balanceAmount;
  final Map<String, Object?> rawData;

  bool get canCancel => status == 0;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(
    createdAtEpochSeconds * 1000,
    isUtc: true,
  ).toLocal();

  DateTime? get paidAt => paidAtEpochSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          paidAtEpochSeconds! * 1000,
          isUtc: true,
        ).toLocal();
}

class XboardUserInfo {
  const XboardUserInfo({
    required this.email,
    required this.balance,
    required this.commissionBalance,
    required this.remindExpire,
    required this.remindTraffic,
    required this.rawData,
    this.avatarUrl,
    this.telegramId,
    this.planId,
    this.expiredAtEpochSeconds,
  });

  final String email;
  final int balance;
  final int commissionBalance;
  final bool remindExpire;
  final bool remindTraffic;
  final Uri? avatarUrl;
  final String? telegramId;
  final int? planId;
  final int? expiredAtEpochSeconds;
  final Map<String, Object?> rawData;

  double get balanceAmount => balance / 100;

  DateTime? get expiresAt => expiredAtEpochSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          expiredAtEpochSeconds! * 1000,
          isUtc: true,
        ).toLocal();
}

class XboardInviteCode {
  const XboardInviteCode({
    required this.code,
    required this.pageViews,
    required this.status,
    required this.createdAtEpochSeconds,
    required this.rawData,
  });

  final String code;
  final int pageViews;
  final int status;
  final int createdAtEpochSeconds;
  final Map<String, Object?> rawData;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(
    createdAtEpochSeconds * 1000,
    isUtc: true,
  ).toLocal();
}

class XboardCommissionRecord {
  const XboardCommissionRecord({
    required this.id,
    required this.orderAmount,
    required this.tradeNo,
    required this.commissionAmount,
    required this.createdAtEpochSeconds,
    required this.rawData,
  });

  final int id;
  final int orderAmount;
  final String tradeNo;
  final int commissionAmount;
  final int createdAtEpochSeconds;
  final Map<String, Object?> rawData;

  double get amount => commissionAmount / 100;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(
    createdAtEpochSeconds * 1000,
    isUtc: true,
  ).toLocal();
}

class XboardInviteSummary {
  const XboardInviteSummary({
    required this.codes,
    required this.registeredUsers,
    required this.confirmedCommission,
    required this.pendingCommission,
    required this.commissionRate,
    required this.availableCommission,
  });

  final List<XboardInviteCode> codes;
  final int registeredUsers;
  final int confirmedCommission;
  final int pendingCommission;
  final int commissionRate;
  final int availableCommission;

  double get confirmedCommissionAmount => confirmedCommission / 100;

  double get pendingCommissionAmount => pendingCommission / 100;

  double get availableCommissionAmount => availableCommission / 100;
}

int xboardTagCount(Iterable<XboardNodeData> nodes) {
  return nodes
      .expand((node) => node.tags)
      .map((tag) => tag.trim().toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .length;
}

String xboardNodeMatchKey(String name) {
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    if (rune >= 0x1F1E6 && rune <= 0x1F1FF) continue;
    if (String.fromCharCode(rune).contains(RegExp(r'[\s\-_·|｜]'))) continue;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

XboardNodeData? matchXboardNodeByName(
  String name,
  Iterable<XboardNodeData> nodes,
) {
  for (final node in nodes) {
    if (node.name == name) return node;
  }
  final matchKey = xboardNodeMatchKey(name);
  if (matchKey.isEmpty) return null;
  for (final node in nodes) {
    if (xboardNodeMatchKey(node.name) == matchKey) return node;
  }
  return null;
}

bool isXboardNodeMarkedOffline(String name, Iterable<XboardNodeData> nodes) {
  return matchXboardNodeByName(name, nodes)?.isOnline == false;
}

class XboardGuestConfig {
  const XboardGuestConfig({
    required this.endpoint,
    required this.isEmailVerify,
    required this.isInviteForce,
    required this.emailWhitelistSuffix,
    required this.rawData,
  });

  final Uri endpoint;
  final bool isEmailVerify;
  final bool isInviteForce;
  final List<String> emailWhitelistSuffix;
  final Map<String, Object?> rawData;

  List<String> get emailDomains =>
      emailWhitelistSuffix.map((suffix) => '@$suffix').toList(growable: false);
}

class XboardRegistrationResult {
  const XboardRegistrationResult({
    required this.endpoint,
    required this.rawData,
    this.token,
    this.authData,
    this.isAdmin = false,
  });

  final Uri endpoint;
  final String? token;
  final String? authData;
  final bool isAdmin;
  final Map<String, Object?> rawData;
}

class XboardLoginResponse {
  const XboardLoginResponse({required this.statusCode, this.data});

  final int statusCode;
  final Object? data;
}

typedef XboardEndpointLoader = Future<List<Uri>> Function();
typedef XboardLoginRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String email,
      String password,
    );
typedef XboardSubscriptionRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardNodesRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardPlansRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardPaymentMethodsRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardOrderSaveRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      int planId,
      String period,
    );
typedef XboardOrderCheckoutRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      String tradeNo,
      int methodId,
    );
typedef XboardOrderCheckRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      String tradeNo,
    );
typedef XboardOrdersRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardNoticesRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardOrderCancelRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      String tradeNo,
    );
typedef XboardUserInfoRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardTrafficLogsRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardInviteRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardCommissionTransferRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      int amount,
    );
typedef XboardTicketSaveRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      String subject,
      int level,
      String message,
    );
typedef XboardUserUpdateRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      bool remindExpire,
      bool remindTraffic,
    );
typedef XboardChangePasswordRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String authData,
      String oldPassword,
      String newPassword,
    );
typedef XboardResetSecurityRequester =
    Future<XboardLoginResponse> Function(Uri endpoint, String authData);
typedef XboardGuestConfigRequester =
    Future<XboardLoginResponse> Function(Uri endpoint);
typedef XboardEmailVerificationRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String email,
      bool isForgetPassword,
    );
typedef XboardRegistrationRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String email,
      String password,
      String emailCode,
    );
typedef XboardPasswordResetRequester =
    Future<XboardLoginResponse> Function(
      Uri endpoint,
      String email,
      String password,
      String emailCode,
    );

class XboardAuthService {
  XboardAuthService({
    ApiHealthService? apiHealthService,
    Dio? dio,
    XboardEndpointLoader? endpointLoader,
    XboardLoginRequester? loginRequester,
    XboardSubscriptionRequester? subscriptionRequester,
    XboardNodesRequester? nodesRequester,
    XboardPlansRequester? plansRequester,
    XboardPaymentMethodsRequester? paymentMethodsRequester,
    XboardOrderSaveRequester? orderSaveRequester,
    XboardOrderCheckoutRequester? orderCheckoutRequester,
    XboardOrderCheckRequester? orderCheckRequester,
    XboardOrdersRequester? ordersRequester,
    XboardOrdersRequester? orderDetailRequester,
    XboardOrderCancelRequester? orderCancelRequester,
    XboardNoticesRequester? noticesRequester,
    XboardUserInfoRequester? userInfoRequester,
    XboardTrafficLogsRequester? trafficLogsRequester,
    XboardInviteRequester? inviteFetchRequester,
    XboardInviteRequester? inviteSaveRequester,
    XboardInviteRequester? inviteDetailsRequester,
    XboardCommissionTransferRequester? commissionTransferRequester,
    XboardTicketSaveRequester? ticketSaveRequester,
    XboardUserUpdateRequester? userUpdateRequester,
    XboardChangePasswordRequester? changePasswordRequester,
    XboardResetSecurityRequester? resetSecurityRequester,
    XboardGuestConfigRequester? guestConfigRequester,
    XboardEmailVerificationRequester? emailVerificationRequester,
    XboardRegistrationRequester? registrationRequester,
    XboardPasswordResetRequester? passwordResetRequester,
    SubscriptionV2Client? subscriptionV2Client,
  }) : _apiHealthService = apiHealthService ?? ApiHealthService(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 8),
             ),
           ),
       _endpointLoader = endpointLoader,
       _loginRequester = loginRequester,
       _subscriptionRequester = subscriptionRequester,
       _nodesRequester = nodesRequester,
       _plansRequester = plansRequester,
       _paymentMethodsRequester = paymentMethodsRequester,
       _orderSaveRequester = orderSaveRequester,
       _orderCheckoutRequester = orderCheckoutRequester,
       _orderCheckRequester = orderCheckRequester,
       _ordersRequester = ordersRequester,
       _orderDetailRequester = orderDetailRequester,
       _orderCancelRequester = orderCancelRequester,
       _noticesRequester = noticesRequester,
       _userInfoRequester = userInfoRequester,
       _trafficLogsRequester = trafficLogsRequester,
       _inviteFetchRequester = inviteFetchRequester,
       _inviteSaveRequester = inviteSaveRequester,
       _inviteDetailsRequester = inviteDetailsRequester,
       _commissionTransferRequester = commissionTransferRequester,
       _ticketSaveRequester = ticketSaveRequester,
       _userUpdateRequester = userUpdateRequester,
       _changePasswordRequester = changePasswordRequester,
       _resetSecurityRequester = resetSecurityRequester,
       _guestConfigRequester = guestConfigRequester,
       _emailVerificationRequester = emailVerificationRequester,
       _registrationRequester = registrationRequester,
       _passwordResetRequester = passwordResetRequester,
       _subscriptionV2Client = subscriptionV2Client;

  final ApiHealthService _apiHealthService;
  final Dio _dio;
  final XboardEndpointLoader? _endpointLoader;
  final XboardLoginRequester? _loginRequester;
  final XboardSubscriptionRequester? _subscriptionRequester;
  final XboardNodesRequester? _nodesRequester;
  final XboardPlansRequester? _plansRequester;
  final XboardPaymentMethodsRequester? _paymentMethodsRequester;
  final XboardOrderSaveRequester? _orderSaveRequester;
  final XboardOrderCheckoutRequester? _orderCheckoutRequester;
  final XboardOrderCheckRequester? _orderCheckRequester;
  final XboardOrdersRequester? _ordersRequester;
  final XboardOrdersRequester? _orderDetailRequester;
  final XboardOrderCancelRequester? _orderCancelRequester;
  final XboardNoticesRequester? _noticesRequester;
  final XboardUserInfoRequester? _userInfoRequester;
  final XboardTrafficLogsRequester? _trafficLogsRequester;
  final XboardInviteRequester? _inviteFetchRequester;
  final XboardInviteRequester? _inviteSaveRequester;
  final XboardInviteRequester? _inviteDetailsRequester;
  final XboardCommissionTransferRequester? _commissionTransferRequester;
  final XboardTicketSaveRequester? _ticketSaveRequester;
  final XboardUserUpdateRequester? _userUpdateRequester;
  final XboardChangePasswordRequester? _changePasswordRequester;
  final XboardResetSecurityRequester? _resetSecurityRequester;
  final XboardGuestConfigRequester? _guestConfigRequester;
  final XboardEmailVerificationRequester? _emailVerificationRequester;
  final XboardRegistrationRequester? _registrationRequester;
  final XboardPasswordResetRequester? _passwordResetRequester;
  final SubscriptionV2Client? _subscriptionV2Client;

  XboardLoginResult? _currentSession;
  XboardGuestConfig? _currentGuestConfig;

  XboardLoginResult? get currentSession => _currentSession;

  XboardGuestConfig? get currentGuestConfig => _currentGuestConfig;

  Future<List<XboardNodeData>> fetchNodes({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardServerFetchUri(endpoint);
    final response = await (_nodesRequester ?? _requestNodes)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '节点接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseNodesSuccess(requestEndpoint, body);
    }
    final message = _responseMessage(body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw XboardAuthException(
        failure: XboardAuthFailure.authenticationRejected,
        message: message ?? '登录状态已失效，请重新登录',
        statusCode: response.statusCode,
        endpoint: requestEndpoint,
      );
    }
    throw XboardAuthException(
      failure: XboardAuthFailure.unavailable,
      message: message ?? '节点接口暂时不可用',
      statusCode: response.statusCode,
      endpoint: requestEndpoint,
    );
  }

  Future<List<XboardAvailablePlan>> fetchPlans({
    required Uri endpoint,
    required String authData,
    int? planId,
  }) async {
    final requestEndpoint = buildXboardPlanFetchUri(endpoint, planId: planId);
    final response = await (_plansRequester ?? _requestPlans)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '套餐接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parsePlansSuccess(requestEndpoint, body);
    }
    final message = _responseMessage(body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw XboardAuthException(
        failure: XboardAuthFailure.authenticationRejected,
        message: message ?? '登录状态已失效，请重新登录',
        statusCode: response.statusCode,
        endpoint: requestEndpoint,
      );
    }
    throw XboardAuthException(
      failure: XboardAuthFailure.unavailable,
      message: message ?? '套餐接口暂时不可用',
      statusCode: response.statusCode,
      endpoint: requestEndpoint,
    );
  }

  Future<List<XboardPaymentMethod>> fetchPaymentMethods({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardPaymentMethodUri(endpoint);
    final response = await (_paymentMethodsRequester ?? _requestPaymentMethods)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '支付方式接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parsePaymentMethodsSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '支付方式暂时不可用',
    );
  }

  Future<String> createOrder({
    required Uri endpoint,
    required String authData,
    required int planId,
    required String period,
  }) async {
    final requestEndpoint = buildXboardOrderSaveUri(endpoint);
    final response = await (_orderSaveRequester ?? _requestOrderSave)(
      requestEndpoint,
      authData,
      planId,
      period,
    );
    final body = _decodeResponseMap(response.data, apiName: '创建订单接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final tradeNo = body['data']?.toString().trim() ?? '';
      if (tradeNo.isEmpty) {
        throw XboardAuthException(
          failure: XboardAuthFailure.invalidResponse,
          message: '创建订单接口未返回订单号',
          endpoint: requestEndpoint,
        );
      }
      return tradeNo;
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订单创建失败，请稍后重试',
    );
  }

  Future<XboardCheckoutResult> checkoutOrder({
    required Uri endpoint,
    required String authData,
    required String tradeNo,
    required int methodId,
  }) async {
    final requestEndpoint = buildXboardOrderCheckoutUri(endpoint);
    final response = await (_orderCheckoutRequester ?? _requestOrderCheckout)(
      requestEndpoint,
      authData,
      tradeNo,
      methodId,
    );
    final body = _decodeResponseMap(response.data, apiName: '订单结算接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final type = _asInt(body['type']);
      if (type == null) {
        throw XboardAuthException(
          failure: XboardAuthFailure.invalidResponse,
          message: '订单结算接口未返回支付类型',
          endpoint: requestEndpoint,
        );
      }
      final result = XboardCheckoutResult(
        type: type,
        data: body['data'],
        rawData: Map.unmodifiable(body),
      );
      if (!result.isFree && result.paymentPayload == null) {
        throw XboardAuthException(
          failure: XboardAuthFailure.invalidResponse,
          message: '订单结算接口未返回支付二维码',
          endpoint: requestEndpoint,
        );
      }
      return result;
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订单结算失败，请稍后重试',
    );
  }

  Future<int> checkOrder({
    required Uri endpoint,
    required String authData,
    required String tradeNo,
  }) async {
    final requestEndpoint = buildXboardOrderCheckUri(endpoint, tradeNo);
    final response = await (_orderCheckRequester ?? _requestOrderCheck)(
      requestEndpoint,
      authData,
      tradeNo,
    );
    final body = _decodeResponseMap(response.data, apiName: '订单状态接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final status = _asInt(body['data']);
      if (status == null) {
        throw XboardAuthException(
          failure: XboardAuthFailure.invalidResponse,
          message: '订单状态接口未返回有效状态',
          endpoint: requestEndpoint,
        );
      }
      return status;
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订单状态检查失败',
    );
  }

  Future<List<XboardOrderData>> fetchOrders({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardOrderFetchUri(endpoint);
    final response = await (_ordersRequester ?? _requestOrders)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '订单列表接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseOrdersSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订单列表暂时不可用',
    );
  }

  Future<XboardOrderData> fetchOrderDetail({
    required Uri endpoint,
    required String authData,
    required String tradeNo,
  }) async {
    final requestEndpoint = buildXboardOrderDetailUri(endpoint, tradeNo);
    final response = await (_orderDetailRequester ?? _requestOrders)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '订单详情接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseOrderDetailSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订单详情暂时不可用',
    );
  }

  Future<void> cancelOrder({
    required Uri endpoint,
    required String authData,
    required String tradeNo,
  }) async {
    final requestEndpoint = buildXboardOrderCancelUri(endpoint);
    final response = await (_orderCancelRequester ?? _requestOrderCancel)(
      requestEndpoint,
      authData,
      tradeNo,
    );
    final body = _decodeResponseMap(response.data, apiName: '取消订单接口');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订单取消失败，请稍后重试',
    );
  }

  Future<List<XboardNoticeData>> fetchNotices({
    required Uri endpoint,
    required String authData,
  }) async {
    final notices = <XboardNoticeData>[];
    final ids = <int>{};
    var current = 1;
    var total = 0;
    do {
      final requestEndpoint = buildXboardNoticeFetchUri(
        endpoint,
        current: current,
      );
      final response = await (_noticesRequester ?? _requestNotices)(
        requestEndpoint,
        authData,
      );
      final body = _decodeResponseMap(response.data, apiName: '公告列表接口');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwAuthenticatedRequestFailure(
          endpoint: requestEndpoint,
          statusCode: response.statusCode,
          body: body,
          fallbackMessage: '公告列表暂时不可用',
        );
      }
      final page = _parseNoticesSuccess(requestEndpoint, body);
      total = page.total;
      for (final notice in page.notices) {
        if (ids.add(notice.id)) notices.add(notice);
      }
      if (page.notices.isEmpty || notices.length >= total) break;
      current++;
    } while (current <= 100);
    return List.unmodifiable(notices);
  }

  Future<XboardUserInfo> fetchUserInfo({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardUserInfoUri(endpoint);
    final response = await (_userInfoRequester ?? _requestUserInfo)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '个人资料接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseUserInfoSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '个人资料暂时不可用',
    );
  }

  Future<XboardSubscriptionData> fetchSubscription({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
  }) async {
    final requestEndpoint = buildXboardSubscribeUri(endpoint);
    if (secureSubscription) {
      final normalizedToken = userToken?.trim() ?? '';
      if (normalizedToken.isEmpty) {
        throw XboardAuthException(
          failure: XboardAuthFailure.authenticationRejected,
          message: '本地安全订阅凭证不完整，请重新登录',
          endpoint: requestEndpoint,
        );
      }
      try {
        final summary = await (_subscriptionV2Client ?? SubscriptionV2Client())
            .fetchSummary(endpoint: endpoint, userToken: normalizedToken);
        return _parseSubscriptionSuccess(requestEndpoint, {'data': summary});
      } on SubscriptionV2Exception catch (error) {
        throw _mapSubscriptionV2Error(error, requestEndpoint);
      }
    }
    final response = await (_subscriptionRequester ?? _requestSubscription)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '订阅信息接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseSubscriptionSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订阅信息暂时不可用',
    );
  }

  Future<List<XboardTrafficLog>> fetchTrafficLogs({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardTrafficLogUri(endpoint);
    final response = await (_trafficLogsRequester ?? _requestTrafficLogs)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '流量明细接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseTrafficLogsSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '流量明细暂时不可用',
    );
  }

  Future<XboardInviteSummary> fetchInviteSummary({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardInviteFetchUri(endpoint);
    final response = await (_inviteFetchRequester ?? _requestInvite)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '邀请统计接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseInviteSummarySuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '邀请统计暂时不可用',
    );
  }

  Future<void> generateInviteCode({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardInviteSaveUri(endpoint);
    final response = await (_inviteSaveRequester ?? _requestInvite)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '生成邀请码接口');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '邀请码生成失败',
    );
  }

  Future<List<XboardCommissionRecord>> fetchInviteDetails({
    required Uri endpoint,
    required String authData,
  }) async {
    final requestEndpoint = buildXboardInviteDetailsUri(endpoint);
    final response = await (_inviteDetailsRequester ?? _requestInvite)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '佣金明细接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseCommissionRecordsSuccess(requestEndpoint, body);
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '佣金明细暂时不可用',
    );
  }

  Future<void> transferCommission({
    required Uri endpoint,
    required String authData,
    required int amount,
  }) async {
    final requestEndpoint = buildXboardCommissionTransferUri(endpoint);
    final response =
        await (_commissionTransferRequester ?? _requestCommissionTransfer)(
          requestEndpoint,
          authData,
          amount,
        );
    final body = _decodeResponseMap(response.data, apiName: '佣金划转接口');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '佣金划转失败',
    );
  }

  Future<void> createTicket({
    required Uri endpoint,
    required String authData,
    required String subject,
    required int level,
    required String message,
  }) async {
    final requestEndpoint = buildXboardTicketSaveUri(endpoint);
    final response = await (_ticketSaveRequester ?? _requestTicketSave)(
      requestEndpoint,
      authData,
      subject,
      level,
      message,
    );
    final body = _decodeResponseMap(response.data, apiName: '创建工单接口');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '提现工单提交失败',
    );
  }

  Future<void> updateUserPreferences({
    required Uri endpoint,
    required String authData,
    required bool remindExpire,
    required bool remindTraffic,
  }) async {
    final requestEndpoint = buildXboardUserUpdateUri(endpoint);
    final response = await (_userUpdateRequester ?? _requestUserUpdate)(
      requestEndpoint,
      authData,
      remindExpire,
      remindTraffic,
    );
    final body = _decodeResponseMap(response.data, apiName: '通知设置接口');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '通知设置保存失败',
    );
  }

  Future<void> changePassword({
    required Uri endpoint,
    required String authData,
    required String oldPassword,
    required String newPassword,
  }) async {
    final requestEndpoint = buildXboardChangePasswordUri(endpoint);
    final response = await (_changePasswordRequester ?? _requestChangePassword)(
      requestEndpoint,
      authData,
      oldPassword,
      newPassword,
    );
    final body = _decodeResponseMap(response.data, apiName: '修改密码接口');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '密码修改失败',
    );
  }

  Future<Uri?> resetSecurity({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
  }) async {
    if (secureSubscription) {
      final normalizedToken = userToken?.trim() ?? '';
      if (normalizedToken.isEmpty) {
        throw XboardAuthException(
          failure: XboardAuthFailure.authenticationRejected,
          message: '本地安全订阅凭证不完整，请重新登录',
          endpoint: endpoint,
        );
      }
      try {
        await (_subscriptionV2Client ?? SubscriptionV2Client()).resetSecurity(
          endpoint: endpoint,
          userToken: normalizedToken,
        );
        return null;
      } on SubscriptionV2Exception catch (error) {
        throw _mapSubscriptionV2Error(error, endpoint);
      }
    }
    final requestEndpoint = buildXboardResetSecurityUri(endpoint);
    final response = await (_resetSecurityRequester ?? _requestResetSecurity)(
      requestEndpoint,
      authData,
    );
    final body = _decodeResponseMap(response.data, apiName: '重置订阅接口');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final rawUrl = body['data']?.toString().trim() ?? '';
      if (rawUrl.isEmpty) return null;
      final subscribeUrl = Uri.tryParse(rawUrl);
      if (subscribeUrl == null ||
          !{'http', 'https'}.contains(subscribeUrl.scheme) ||
          subscribeUrl.host.isEmpty) {
        throw XboardAuthException(
          failure: XboardAuthFailure.invalidResponse,
          message: '重置订阅接口未返回有效订阅地址',
          endpoint: requestEndpoint,
        );
      }
      return subscribeUrl;
    }
    _throwAuthenticatedRequestFailure(
      endpoint: requestEndpoint,
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: '订阅信息重置失败',
    );
  }

  Never _throwAuthenticatedRequestFailure({
    required Uri endpoint,
    required int statusCode,
    required Map<String, Object?> body,
    required String fallbackMessage,
  }) {
    final message = _responseMessage(body);
    throw XboardAuthException(
      failure: statusCode == 401 || statusCode == 403
          ? XboardAuthFailure.authenticationRejected
          : XboardAuthFailure.unavailable,
      message: message ?? fallbackMessage,
      statusCode: statusCode,
      endpoint: endpoint,
    );
  }

  Future<XboardRegistrationResult> register({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    final availableEndpoints =
        await (_endpointLoader ?? _loadAvailableEndpoints)();
    if (availableEndpoints.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.noAvailableHost,
        message: '当前没有可用的 API 节点，无法注册',
      );
    }
    final currentEndpoint = _currentGuestConfig?.endpoint;
    final endpoints = <Uri>[
      ?currentEndpoint,
      ...availableEndpoints.where(
        (endpoint) =>
            currentEndpoint == null ||
            endpoint.authority != currentEndpoint.authority,
      ),
    ];

    XboardAuthException? lastFailure;
    for (final baseEndpoint in endpoints) {
      final endpoint = buildXboardRegisterUri(baseEndpoint);
      try {
        final response = await (_registrationRequester ?? _requestRegistration)(
          endpoint,
          email.trim(),
          password,
          emailCode.trim(),
        );
        final statusCode = response.statusCode;
        late final Map<String, Object?> body;
        try {
          body = _decodeResponseMap(response.data, apiName: '注册接口');
        } on XboardAuthException {
          if (statusCode >= 200 && statusCode < 300) rethrow;
          body = const {};
        }

        if (statusCode >= 200 && statusCode < 300) {
          return _parseRegistrationSuccess(endpoint, body);
        }

        final message = _responseMessage(body);
        if (statusCode == 429) {
          throw XboardAuthException(
            failure: XboardAuthFailure.rateLimited,
            message: message ?? '注册操作过于频繁，请稍后再试',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        if (statusCode >= 400 && statusCode < 500 && statusCode != 404) {
          throw XboardAuthException(
            failure: XboardAuthFailure.registrationRejected,
            message: message ?? '注册失败，请检查填写的信息',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: message ?? '注册接口暂时不可用',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      } on XboardAuthException catch (error) {
        if (error.failure == XboardAuthFailure.registrationRejected ||
            error.failure == XboardAuthFailure.rateLimited ||
            error.failure == XboardAuthFailure.invalidResponse) {
          rethrow;
        }
        lastFailure = error;
      } on DioException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '注册接口连接失败',
          endpoint: endpoint,
        );
      } on TimeoutException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '注册接口连接超时',
          endpoint: endpoint,
        );
      } catch (_) {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '注册请求失败',
          endpoint: endpoint,
        );
      }
    }

    throw lastFailure ??
        const XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '所有注册接口均不可用，请稍后重试',
        );
  }

  Future<void> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    final availableEndpoints =
        await (_endpointLoader ?? _loadAvailableEndpoints)();
    if (availableEndpoints.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.noAvailableHost,
        message: '当前没有可用的 API 节点，无法重置密码',
      );
    }
    final currentEndpoint = _currentGuestConfig?.endpoint;
    final endpoints = <Uri>[
      ?currentEndpoint,
      ...availableEndpoints.where(
        (endpoint) =>
            currentEndpoint == null ||
            endpoint.authority != currentEndpoint.authority,
      ),
    ];

    XboardAuthException? lastFailure;
    for (final baseEndpoint in endpoints) {
      final endpoint = buildXboardForgetPasswordUri(baseEndpoint);
      try {
        final response =
            await (_passwordResetRequester ?? _requestPasswordReset)(
              endpoint,
              email.trim(),
              password,
              emailCode.trim(),
            );
        final statusCode = response.statusCode;
        late final Map<String, Object?> body;
        try {
          body = _decodeResponseMap(response.data, apiName: '重置密码接口');
        } on XboardAuthException {
          if (statusCode >= 200 && statusCode < 300) rethrow;
          body = const {};
        }
        if (statusCode >= 200 && statusCode < 300) return;

        final message = _responseMessage(body);
        if (statusCode == 429) {
          throw XboardAuthException(
            failure: XboardAuthFailure.rateLimited,
            message: message ?? '重置密码操作过于频繁，请稍后再试',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        if (statusCode >= 400 && statusCode < 500 && statusCode != 404) {
          throw XboardAuthException(
            failure: XboardAuthFailure.passwordResetRejected,
            message: message ?? '重置密码失败，请检查邮箱和验证码',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: message ?? '重置密码接口暂时不可用',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      } on XboardAuthException catch (error) {
        if (error.failure == XboardAuthFailure.passwordResetRejected ||
            error.failure == XboardAuthFailure.rateLimited ||
            error.failure == XboardAuthFailure.invalidResponse) {
          rethrow;
        }
        lastFailure = error;
      } on DioException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '重置密码接口连接失败',
          endpoint: endpoint,
        );
      } on TimeoutException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '重置密码接口连接超时',
          endpoint: endpoint,
        );
      } catch (_) {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '重置密码请求失败',
          endpoint: endpoint,
        );
      }
    }

    throw lastFailure ??
        const XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '所有重置密码接口均不可用，请稍后重试',
        );
  }

  Future<void> sendEmailVerification({
    required String email,
    bool isForgetPassword = false,
  }) async {
    final availableEndpoints =
        await (_endpointLoader ?? _loadAvailableEndpoints)();
    if (availableEndpoints.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.noAvailableHost,
        message: '当前没有可用的 API 节点，无法发送验证码',
      );
    }
    final currentEndpoint = _currentGuestConfig?.endpoint;
    final endpoints = <Uri>[
      ?currentEndpoint,
      ...availableEndpoints.where(
        (endpoint) =>
            currentEndpoint == null ||
            endpoint.authority != currentEndpoint.authority,
      ),
    ];

    XboardAuthException? lastFailure;
    for (final baseEndpoint in endpoints) {
      final endpoint = buildXboardSendEmailVerifyUri(baseEndpoint);
      try {
        final response =
            await (_emailVerificationRequester ?? _requestEmailVerification)(
              endpoint,
              email.trim(),
              isForgetPassword,
            );
        final statusCode = response.statusCode;
        late final Map<String, Object?> body;
        try {
          body = _decodeResponseMap(response.data, apiName: '邮箱验证码接口');
        } on XboardAuthException {
          if (statusCode >= 200 && statusCode < 300) rethrow;
          body = const {};
        }
        if (statusCode >= 200 && statusCode < 300) return;

        final message = _responseMessage(body);
        if (statusCode >= 400 && statusCode < 500 && statusCode != 404) {
          throw XboardAuthException(
            failure: XboardAuthFailure.verificationRejected,
            message: message ?? '验证码发送失败，请稍后重试',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: message ?? '邮箱验证码接口暂时不可用',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      } on XboardAuthException catch (error) {
        if (error.failure == XboardAuthFailure.verificationRejected ||
            error.failure == XboardAuthFailure.invalidResponse) {
          rethrow;
        }
        lastFailure = error;
      } on DioException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '邮箱验证码接口连接失败',
          endpoint: endpoint,
        );
      } on TimeoutException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '邮箱验证码接口连接超时',
          endpoint: endpoint,
        );
      } catch (_) {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '邮箱验证码请求失败',
          endpoint: endpoint,
        );
      }
    }

    throw lastFailure ??
        const XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '所有邮箱验证码接口均不可用，请稍后重试',
        );
  }

  Future<XboardGuestConfig> loadGuestConfig() async {
    final endpoints = await (_endpointLoader ?? _loadAvailableEndpoints)();
    if (endpoints.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.noAvailableHost,
        message: '当前没有可用的 API 节点，无法获取注册配置',
      );
    }

    XboardAuthException? lastFailure;
    for (final baseEndpoint in endpoints) {
      final endpoint = buildXboardGuestConfigUri(baseEndpoint);
      try {
        final response = await (_guestConfigRequester ?? _requestGuestConfig)(
          endpoint,
        );
        final statusCode = response.statusCode;
        late final Map<String, Object?> body;
        try {
          body = _decodeResponseMap(response.data, apiName: '注册配置接口');
        } on XboardAuthException {
          if (statusCode >= 200 && statusCode < 300) rethrow;
          body = const {};
        }
        if (statusCode >= 200 && statusCode < 300) {
          final config = _parseGuestConfigSuccess(endpoint, body);
          _currentGuestConfig = config;
          return config;
        }
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: _responseMessage(body) ?? '注册配置接口暂时不可用',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      } on XboardAuthException catch (error) {
        if (error.failure == XboardAuthFailure.invalidResponse) rethrow;
        lastFailure = error;
      } on DioException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '注册配置接口连接失败',
          endpoint: endpoint,
        );
      } on TimeoutException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '注册配置接口连接超时',
          endpoint: endpoint,
        );
      } catch (_) {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '注册配置请求失败',
          endpoint: endpoint,
        );
      }
    }

    throw lastFailure ??
        const XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '所有注册配置接口均不可用，请稍后重试',
        );
  }

  Future<XboardLoginResult> restoreSession({
    required Uri preferredEndpoint,
    required String token,
    required String authData,
    bool isAdmin = false,
    bool secureSubscription = false,
  }) async {
    final normalizedToken = token.trim();
    final normalizedAuthData = authData.trim();
    if (normalizedToken.isEmpty || normalizedAuthData.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.invalidResponse,
        message: '本地登录凭证不完整',
      );
    }
    final availableEndpoints =
        await (_endpointLoader ?? _loadAvailableEndpoints)();
    final preferredBaseEndpoint = _asXboardBaseEndpoint(preferredEndpoint);
    final configuredPreferred = _endpointLoader == null
        ? await _apiHealthService.loadPreferredEndpoint()
        : null;
    final configuredPreferredAvailable =
        configuredPreferred != null &&
        availableEndpoints.any(
          (endpoint) => isSameApiEndpoint(endpoint, configuredPreferred),
        );
    final endpoints = configuredPreferredAvailable
        ? <Uri>[
            ...availableEndpoints,
            if (preferredBaseEndpoint != null &&
                !availableEndpoints.any(
                  (endpoint) =>
                      isSameApiEndpoint(endpoint, preferredBaseEndpoint),
                ))
              preferredBaseEndpoint,
          ]
        : <Uri>[
            ?preferredBaseEndpoint,
            ...availableEndpoints.where(
              (endpoint) =>
                  preferredBaseEndpoint == null ||
                  !isSameApiEndpoint(endpoint, preferredBaseEndpoint),
            ),
          ];
    if (endpoints.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.noAvailableHost,
        message: '当前没有可用的 API 节点，无法恢复登录',
      );
    }
    final auth = _XboardAuthData(
      endpoint: buildXboardLoginUri(endpoints.first),
      token: normalizedToken,
      authData: normalizedAuthData,
      isAdmin: isAdmin,
      rawData: Map.unmodifiable({
        'token': normalizedToken,
        'auth_data': normalizedAuthData,
        'is_admin': isAdmin,
      }),
    );
    late final XboardSubscriptionData subscription;
    if (secureSubscription) {
      subscription = await fetchSubscription(
        endpoint: endpoints.first,
        authData: normalizedAuthData,
        userToken: normalizedToken,
        secureSubscription: true,
      );
    } else {
      subscription = await _fetchSubscription(
        auth: auth,
        preferredEndpoint: endpoints.first,
        endpoints: endpoints,
      );
    }
    final result = XboardLoginResult(
      endpoint: auth.endpoint,
      token: auth.token,
      authData: auth.authData,
      isAdmin: auth.isAdmin,
      subscription: subscription,
      secureSubscription: secureSubscription,
      rawData: auth.rawData,
    );
    _currentSession = result;
    return result;
  }

  Future<XboardLoginResult> login({
    required String email,
    required String password,
    String appVersion = 'unknown',
    String? platform,
  }) async {
    final endpoints = await (_endpointLoader ?? _loadAvailableEndpoints)();
    if (endpoints.isEmpty) {
      throw const XboardAuthException(
        failure: XboardAuthFailure.noAvailableHost,
        message: '当前没有可用的 API 节点，请刷新后重试',
      );
    }

    final secureClient = _subscriptionV2Client;
    if (secureClient != null) {
      XboardAuthException? secureFailure;
      var useLegacyLogin = false;
      for (final baseEndpoint in endpoints) {
        final loginEndpoint = buildXboardLoginUri(baseEndpoint);
        try {
          final secure = await secureClient.secureLogin(
            endpoint: baseEndpoint,
            email: email,
            password: password,
            appVersion: appVersion,
            platform: platform,
          );
          if (secure == null) {
            useLegacyLogin = true;
            break;
          }
          final subscription = _parseSubscriptionSuccess(loginEndpoint, {
            'data': secure.subscription,
          });
          final result = XboardLoginResult(
            endpoint: loginEndpoint,
            token: secure.token,
            authData: secure.authData,
            isAdmin: secure.isAdmin,
            subscription: subscription,
            secureSubscription: true,
            rawData: secure.rawData,
          );
          _currentSession = result;
          return result;
        } on SubscriptionV2Exception catch (error) {
          final mapped = _mapSubscriptionV2Error(error, loginEndpoint);
          if (error.code != 'gateway_unavailable' &&
              error.code != 'temporary_unavailable') {
            throw mapped;
          }
          secureFailure = mapped;
        } on DioException {
          secureFailure = XboardAuthException(
            failure: XboardAuthFailure.unavailable,
            message: '安全登录网关连接失败',
            endpoint: loginEndpoint,
          );
        } on TimeoutException {
          secureFailure = XboardAuthException(
            failure: XboardAuthFailure.unavailable,
            message: '安全登录网关连接超时',
            endpoint: loginEndpoint,
          );
        } on FormatException {
          secureFailure = XboardAuthException(
            failure: XboardAuthFailure.unavailable,
            message: '安全登录配置校验失败',
            endpoint: loginEndpoint,
          );
        } catch (_) {
          secureFailure = XboardAuthException(
            failure: XboardAuthFailure.unavailable,
            message: '安全登录请求失败',
            endpoint: loginEndpoint,
          );
        }
      }
      if (!useLegacyLogin && secureFailure != null) {
        throw secureFailure;
      }
    }

    XboardAuthException? lastFailure;
    for (final baseEndpoint in endpoints) {
      final loginEndpoint = buildXboardLoginUri(baseEndpoint);
      try {
        final response = await (_loginRequester ?? _requestLogin)(
          loginEndpoint,
          email.trim(),
          password,
        );
        final statusCode = response.statusCode;
        late final Map<String, Object?> body;
        try {
          body = _decodeResponseMap(response.data);
        } on XboardAuthException {
          if (statusCode >= 200 && statusCode < 300) rethrow;
          body = const {};
        }

        if (statusCode >= 200 && statusCode < 300) {
          final auth = _parseLoginSuccess(loginEndpoint, body);
          final subscription = await _fetchSubscription(
            auth: auth,
            preferredEndpoint: baseEndpoint,
            endpoints: endpoints,
          );
          final result = XboardLoginResult(
            endpoint: auth.endpoint,
            token: auth.token,
            authData: auth.authData,
            isAdmin: auth.isAdmin,
            subscription: subscription,
            secureSubscription: false,
            rawData: auth.rawData,
          );
          _currentSession = result;
          return result;
        }

        final message = _responseMessage(body);
        if (statusCode == 429) {
          throw XboardAuthException(
            failure: XboardAuthFailure.rateLimited,
            message: message ?? '登录尝试过于频繁，请稍后再试',
            statusCode: statusCode,
            endpoint: loginEndpoint,
          );
        }
        if (statusCode >= 400 && statusCode < 500 && statusCode != 404) {
          throw XboardAuthException(
            failure: XboardAuthFailure.authenticationRejected,
            message: message ?? '邮箱或密码错误',
            statusCode: statusCode,
            endpoint: loginEndpoint,
          );
        }

        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: message ?? 'API 节点暂时不可用',
          statusCode: statusCode,
          endpoint: loginEndpoint,
        );
      } on XboardAuthException catch (error) {
        if (error.failure == XboardAuthFailure.authenticationRejected ||
            error.failure == XboardAuthFailure.rateLimited ||
            error.failure == XboardAuthFailure.subscriptionRejected ||
            error.failure == XboardAuthFailure.subscriptionUnavailable ||
            error.failure == XboardAuthFailure.invalidResponse) {
          rethrow;
        }
        lastFailure = error;
      } on DioException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: 'API 节点连接失败',
          endpoint: loginEndpoint,
        );
      } on TimeoutException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: 'API 节点连接超时',
          endpoint: loginEndpoint,
        );
      } catch (_) {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: 'API 节点请求失败',
          endpoint: loginEndpoint,
        );
      }
    }

    throw lastFailure ??
        const XboardAuthException(
          failure: XboardAuthFailure.unavailable,
          message: '所有 API 节点均不可用，请稍后重试',
        );
  }

  XboardAuthException _mapSubscriptionV2Error(
    SubscriptionV2Exception error,
    Uri endpoint,
  ) {
    if (error.code == 'invalid_credentials') {
      return XboardAuthException(
        failure: XboardAuthFailure.authenticationRejected,
        message: '邮箱或密码错误',
        endpoint: endpoint,
      );
    }
    if (error.code == 'rate_limited') {
      return XboardAuthException(
        failure: XboardAuthFailure.rateLimited,
        message: '登录尝试过于频繁，请稍后再试',
        endpoint: endpoint,
      );
    }
    if (error.code == 'device_limit_reached') {
      return XboardAuthException(
        failure: XboardAuthFailure.authenticationRejected,
        message: '已达到安全设备数量上限，请先在已登录设备退出账号',
        endpoint: endpoint,
      );
    }
    if (error.code == 'device_not_registered' ||
        error.code == 'secure_config_disabled') {
      return XboardAuthException(
        failure: XboardAuthFailure.authenticationRejected,
        message: '安全设备凭证已失效，请重新登录',
        endpoint: endpoint,
      );
    }
    if (error.code == 'subscription_unavailable') {
      return XboardAuthException(
        failure: XboardAuthFailure.subscriptionUnavailable,
        message: '当前订阅不可用',
        endpoint: endpoint,
      );
    }
    return XboardAuthException(
      failure: XboardAuthFailure.unavailable,
      message: '安全订阅服务暂时不可用，请稍后重试',
      endpoint: endpoint,
    );
  }

  Future<List<Uri>> _loadAvailableEndpoints() async {
    final snapshot = await _apiHealthService.check();
    final reachable = await _apiHealthService.orderedReachableEndpoints(
      snapshot,
    );
    return List.unmodifiable(reachable.map((endpoint) => endpoint.endpoint));
  }

  Future<XboardSubscriptionData> _fetchSubscription({
    required _XboardAuthData auth,
    required Uri preferredEndpoint,
    required List<Uri> endpoints,
  }) async {
    final orderedEndpoints = <Uri>[
      preferredEndpoint,
      ...endpoints.where((endpoint) => endpoint != preferredEndpoint),
    ];
    XboardAuthException? lastFailure;
    for (final baseEndpoint in orderedEndpoints) {
      final endpoint = buildXboardSubscribeUri(baseEndpoint);
      try {
        final response = await (_subscriptionRequester ?? _requestSubscription)(
          endpoint,
          auth.authData,
        );
        final statusCode = response.statusCode;
        late final Map<String, Object?> body;
        try {
          body = _decodeResponseMap(response.data, apiName: '订阅信息接口');
        } on XboardAuthException {
          if (statusCode >= 200 && statusCode < 300) rethrow;
          body = const {};
        }

        if (statusCode >= 200 && statusCode < 300) {
          return _parseSubscriptionSuccess(endpoint, body);
        }

        final message = _responseMessage(body);
        if (statusCode == 401 || statusCode == 403) {
          throw XboardAuthException(
            failure: XboardAuthFailure.authenticationRejected,
            message: message ?? '登录状态已失效，请重新登录',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        if (statusCode >= 400 && statusCode < 500 && statusCode != 404) {
          throw XboardAuthException(
            failure: XboardAuthFailure.subscriptionRejected,
            message: message ?? '无法获取订阅信息',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }

        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.subscriptionUnavailable,
          message: message ?? '订阅信息接口暂时不可用',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      } on XboardAuthException catch (error) {
        if (error.failure == XboardAuthFailure.authenticationRejected ||
            error.failure == XboardAuthFailure.subscriptionRejected ||
            error.failure == XboardAuthFailure.invalidResponse) {
          rethrow;
        }
        lastFailure = error;
      } on DioException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.subscriptionUnavailable,
          message: '订阅信息接口连接失败',
          endpoint: endpoint,
        );
      } on TimeoutException {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.subscriptionUnavailable,
          message: '订阅信息接口连接超时',
          endpoint: endpoint,
        );
      } catch (_) {
        lastFailure = XboardAuthException(
          failure: XboardAuthFailure.subscriptionUnavailable,
          message: '订阅信息请求失败',
          endpoint: endpoint,
        );
      }
    }

    throw lastFailure ??
        const XboardAuthException(
          failure: XboardAuthFailure.subscriptionUnavailable,
          message: '所有订阅信息接口均不可用，请稍后重试',
        );
  }

  Future<XboardLoginResponse> _requestLogin(
    Uri endpoint,
    String email,
    String password,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({'email': email, 'password': password}),
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestSubscription(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: Options(
        headers: {'Authorization': authData},
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestNodes(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: Options(
        headers: {'Authorization': authData},
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestPlans(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: Options(
        headers: {'Authorization': authData},
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestPaymentMethods(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestOrderSave(
    Uri endpoint,
    String authData,
    int planId,
    String period,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({'plan_id': planId, 'period': period}),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestOrderCheckout(
    Uri endpoint,
    String authData,
    String tradeNo,
    int methodId,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({'trade_no': tradeNo, 'method': methodId}),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestOrderCheck(
    Uri endpoint,
    String authData,
    String tradeNo,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestOrders(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestOrderCancel(
    Uri endpoint,
    String authData,
    String tradeNo,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({'trade_no': tradeNo}),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestNotices(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestUserInfo(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestTrafficLogs(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestInvite(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestCommissionTransfer(
    Uri endpoint,
    String authData,
    int amount,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({'transfer_amount': amount}),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestTicketSave(
    Uri endpoint,
    String authData,
    String subject,
    int level,
    String message,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({
        'subject': subject,
        'level': level,
        'message': message,
      }),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestUserUpdate(
    Uri endpoint,
    String authData,
    bool remindExpire,
    bool remindTraffic,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({
        'remind_expire': remindExpire ? 1 : 0,
        'remind_traffic': remindTraffic ? 1 : 0,
      }),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestChangePassword(
    Uri endpoint,
    String authData,
    String oldPassword,
    String newPassword,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestResetSecurity(
    Uri endpoint,
    String authData,
  ) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: _authenticatedOptions(authData),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Options _authenticatedOptions(String authData) {
    return Options(
      headers: {'Authorization': authData},
      responseType: ResponseType.json,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 600,
    );
  }

  Future<XboardLoginResponse> _requestGuestConfig(Uri endpoint) async {
    final response = await _dio.getUri<Object?>(
      endpoint,
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestEmailVerification(
    Uri endpoint,
    String email,
    bool isForgetPassword,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({
        'email': email,
        'isForgetPassword': isForgetPassword,
      }),
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestRegistration(
    Uri endpoint,
    String email,
    String password,
    String emailCode,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({
        'email': email,
        'password': password,
        'email_code': emailCode,
      }),
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  Future<XboardLoginResponse> _requestPasswordReset(
    Uri endpoint,
    String email,
    String password,
    String emailCode,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: FormData.fromMap({
        'email': email,
        'password': password,
        'email_code': emailCode,
      }),
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    return XboardLoginResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }
}

Uri buildXboardLoginUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardLoginPath);
}

Uri buildXboardSubscribeUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardSubscribePath);
}

Uri buildXboardServerFetchUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardServerFetchPath);
}

Uri buildXboardPlanFetchUri(Uri baseEndpoint, {int? planId}) {
  final endpoint = baseEndpoint.resolve(xboardPlanFetchPath);
  if (planId == null) return endpoint;
  return endpoint.replace(queryParameters: {'id': planId.toString()});
}

Uri buildXboardOrderSaveUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardOrderSavePath);
}

Uri buildXboardPaymentMethodUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardPaymentMethodPath);
}

Uri buildXboardOrderCheckoutUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardOrderCheckoutPath);
}

Uri buildXboardOrderCheckUri(Uri baseEndpoint, String tradeNo) {
  return baseEndpoint
      .resolve(xboardOrderCheckPath)
      .replace(queryParameters: {'trade_no': tradeNo});
}

Uri buildXboardOrderFetchUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardOrderFetchPath);
}

Uri buildXboardOrderDetailUri(Uri baseEndpoint, String tradeNo) {
  return baseEndpoint
      .resolve(xboardOrderDetailPath)
      .replace(queryParameters: {'trade_no': tradeNo});
}

Uri buildXboardOrderCancelUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardOrderCancelPath);
}

Uri buildXboardNoticeFetchUri(Uri baseEndpoint, {int current = 1}) {
  return baseEndpoint
      .resolve(xboardNoticeFetchPath)
      .replace(
        queryParameters: {'current': current.clamp(1, 1000000).toString()},
      );
}

Uri buildXboardUserInfoUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardUserInfoPath);
}

Uri buildXboardUserUpdateUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardUserUpdatePath);
}

Uri buildXboardChangePasswordUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardChangePasswordPath);
}

Uri buildXboardResetSecurityUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardResetSecurityPath);
}

Uri buildXboardTrafficLogUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardTrafficLogPath);
}

Uri buildXboardInviteFetchUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardInviteFetchPath);
}

Uri buildXboardInviteSaveUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardInviteSavePath);
}

Uri buildXboardInviteDetailsUri(Uri baseEndpoint) {
  return baseEndpoint
      .resolve(xboardInviteDetailsPath)
      .replace(queryParameters: const {'current': '1', 'page_size': '50'});
}

Uri buildXboardCommissionTransferUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardCommissionTransferPath);
}

Uri buildXboardTicketSaveUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardTicketSavePath);
}

Uri buildXboardGuestConfigUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardGuestConfigPath);
}

Uri buildXboardSendEmailVerifyUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardSendEmailVerifyPath);
}

Uri buildXboardRegisterUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardRegisterPath);
}

Uri buildXboardForgetPasswordUri(Uri baseEndpoint) {
  return baseEndpoint.resolve(xboardForgetPasswordPath);
}

Map<String, Object?> _decodeResponseMap(
  Object? response, {
  String apiName = '登录接口',
}) {
  Object? decoded = response;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      throw const XboardAuthException(
        failure: XboardAuthFailure.invalidResponse,
        message: '接口返回了无法识别的数据',
      );
    }
  }
  if (decoded is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '$apiName返回格式不正确',
    );
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

_XboardAuthData _parseLoginSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '登录成功响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final data = rawData.map((key, value) => MapEntry(key.toString(), value));
  final token = data['token']?.toString().trim() ?? '';
  final authData = data['auth_data']?.toString().trim() ?? '';
  if (token.isEmpty || authData.isEmpty) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '登录成功响应缺少授权信息',
      endpoint: endpoint,
    );
  }
  final rawIsAdmin = data['is_admin'];
  final isAdmin = rawIsAdmin == true || rawIsAdmin == 1 || rawIsAdmin == '1';
  return _XboardAuthData(
    endpoint: endpoint,
    token: token,
    authData: authData,
    isAdmin: isAdmin,
    rawData: Map.unmodifiable(data),
  );
}

XboardSubscriptionData _parseSubscriptionSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '订阅信息响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final data = rawData.map((key, value) => MapEntry(key.toString(), value));
  final subscribeUrlText = _asString(data['subscribe_url']);
  final subscribeUrl = subscribeUrlText == null
      ? null
      : Uri.tryParse(subscribeUrlText);
  if (subscribeUrlText != null &&
      (subscribeUrl == null ||
          !{'http', 'https'}.contains(subscribeUrl.scheme) ||
          subscribeUrl.host.isEmpty)) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '订阅信息响应缺少有效的 subscribe_url',
      endpoint: endpoint,
    );
  }

  final rawPlan = data['plan'];
  XboardPlanData? plan;
  if (rawPlan is Map) {
    final planData = rawPlan.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    plan = XboardPlanData(
      id: _asInt(planData['id']),
      name: _asString(planData['name']),
      transferEnableBytes: _asInt(planData['transfer_enable']),
      rawData: Map.unmodifiable(planData),
    );
  }

  final rawExpiredAt = _asEpochSeconds(data['expired_at']);
  return XboardSubscriptionData(
    endpoint: endpoint,
    subscribeUrl: subscribeUrl,
    planId: _asInt(data['plan_id']),
    token: _asString(data['token']),
    email: _asString(data['email']),
    uuid: _asString(data['uuid']),
    expiredAtEpochSeconds: rawExpiredAt == null || rawExpiredAt <= 0
        ? null
        : rawExpiredAt,
    uploadBytes: _asInt(data['u']) ?? 0,
    downloadBytes: _asInt(data['d']) ?? 0,
    transferEnableBytes: _asInt(data['transfer_enable']) ?? 0,
    deviceLimit: _asInt(data['device_limit']),
    speedLimit: _asInt(data['speed_limit']),
    nextResetAtEpochSeconds: _asInt(data['next_reset_at']),
    resetDay: _asInt(data['reset_day']),
    plan: plan,
    rawData: Map.unmodifiable(data),
  );
}

List<XboardNodeData> _parseNodesSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! List) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '节点接口响应缺少 data 数组',
      endpoint: endpoint,
    );
  }
  final nodes = <XboardNodeData>[];
  for (final rawNode in rawData) {
    if (rawNode is! Map) continue;
    final data = rawNode.map((key, value) => MapEntry(key.toString(), value));
    final name = _asString(data['name']);
    if (name == null) continue;
    nodes.add(
      XboardNodeData(
        id: _asInt(data['id']),
        name: name,
        type: _asString(data['type']) ?? '',
        rate: _asDouble(data['rate']) ?? 1,
        tags: List.unmodifiable(_normalizeTags(data['tags'] ?? data['tag'])),
        isOnline: _asBool(data['is_online']),
        rawData: Map.unmodifiable(data),
      ),
    );
  }
  return List.unmodifiable(nodes);
}

List<XboardTrafficLog> _parseTrafficLogsSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! List) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '流量明细响应缺少 data 数组',
      endpoint: endpoint,
    );
  }
  final records = <XboardTrafficLog>[];
  for (final rawRecord in rawData) {
    if (rawRecord is! Map) continue;
    final data = rawRecord.map((key, value) => MapEntry(key.toString(), value));
    final recordAt = _asInt(data['record_at']);
    if (recordAt == null || recordAt <= 0) continue;
    final downloadBytes = _asInt(data['d']) ?? 0;
    final uploadBytes = _asInt(data['u']) ?? 0;
    final serverRate = _asDouble(data['server_rate']) ?? 1;
    records.add(
      XboardTrafficLog(
        downloadBytes: downloadBytes < 0 ? 0 : downloadBytes,
        uploadBytes: uploadBytes < 0 ? 0 : uploadBytes,
        recordAtEpochSeconds: recordAt,
        serverRate: !serverRate.isFinite || serverRate < 0
            ? 0
            : serverRate.clamp(0, 100000),
        rawData: Map.unmodifiable(data),
      ),
    );
  }
  records.sort(
    (a, b) => b.recordAtEpochSeconds.compareTo(a.recordAtEpochSeconds),
  );
  return List.unmodifiable(records);
}

({List<XboardNoticeData> notices, int total}) _parseNoticesSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! List) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '公告列表响应缺少 data 数组',
      endpoint: endpoint,
    );
  }
  final notices = <XboardNoticeData>[];
  for (final rawNotice in rawData) {
    if (rawNotice is! Map) continue;
    final data = rawNotice.map((key, value) => MapEntry(key.toString(), value));
    final id = _asInt(data['id']);
    final title = _asString(data['title']);
    if (id == null || title == null) continue;
    final imageUrlText = _asString(data['img_url'] ?? data['image_url']);
    final parsedImageUrl = imageUrlText == null
        ? null
        : Uri.tryParse(imageUrlText);
    final resolvedImageUrl = parsedImageUrl == null
        ? null
        : parsedImageUrl.hasScheme
        ? parsedImageUrl
        : endpoint.resolveUri(parsedImageUrl);
    final imageUrl =
        resolvedImageUrl != null &&
            {'http', 'https'}.contains(resolvedImageUrl.scheme)
        ? resolvedImageUrl
        : null;
    notices.add(
      XboardNoticeData(
        id: id,
        title: title,
        content: _asString(data['content']) ?? '',
        tags: List.unmodifiable(_normalizeTags(data['tags'])),
        createdAtEpochSeconds: _asEpochSeconds(data['created_at']),
        updatedAtEpochSeconds: _asEpochSeconds(data['updated_at']),
        imageUrl: imageUrl,
        rawData: Map.unmodifiable(data),
      ),
    );
  }
  final total = (_asInt(response['total']) ?? notices.length).clamp(
    notices.length,
    1000000,
  );
  return (notices: List.unmodifiable(notices), total: total);
}

List<XboardAvailablePlan> _parsePlansSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  final rawPlans = switch (rawData) {
    final List<Object?> values => values,
    final Map<Object?, Object?> value => <Object?>[value],
    _ => null,
  };
  if (rawPlans == null) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '套餐接口响应缺少套餐数据',
      endpoint: endpoint,
    );
  }
  const priceKeys = [
    'month_price',
    'quarter_price',
    'half_year_price',
    'year_price',
    'two_year_price',
    'three_year_price',
    'onetime_price',
    'reset_price',
  ];
  final plans = <XboardAvailablePlan>[];
  for (final rawPlan in rawPlans) {
    if (rawPlan is! Map) continue;
    final data = rawPlan.map((key, value) => MapEntry(key.toString(), value));
    final id = _asInt(data['id']);
    final name = _asString(data['name']);
    if (id == null || name == null) continue;
    final prices = <String, int>{};
    for (final key in priceKeys) {
      final price = _asInt(data[key]);
      if (price != null && price >= 0) prices[key] = price;
    }
    final capacity = data['capacity_limit'];
    plans.add(
      XboardAvailablePlan(
        id: id,
        name: name,
        tags: List.unmodifiable(_normalizeTags(data['tags'])),
        content: _asString(data['content']) ?? '',
        transferEnableGb: _asDouble(data['transfer_enable']) ?? 0,
        speedLimit: _asInt(data['speed_limit']),
        deviceLimit: _asInt(data['device_limit']),
        prices: Map.unmodifiable(prices),
        sell: data['sell'] == null || _asBool(data['sell']),
        renew: data['renew'] == null || _asBool(data['renew']),
        isSoldOut:
            (capacity is num && capacity <= 0) ||
            capacity?.toString().toLowerCase().contains('sold out') == true,
        rawData: Map.unmodifiable(data),
      ),
    );
  }
  return List.unmodifiable(plans);
}

List<XboardPaymentMethod> _parsePaymentMethodsSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! List) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '支付方式接口响应缺少 data 数组',
      endpoint: endpoint,
    );
  }
  final methods = <XboardPaymentMethod>[];
  for (final rawMethod in rawData) {
    if (rawMethod is! Map) continue;
    final data = rawMethod.map((key, value) => MapEntry(key.toString(), value));
    final id = _asInt(data['id']);
    final name = _asString(data['name']);
    if (id == null || name == null) continue;
    methods.add(
      XboardPaymentMethod(
        id: id,
        name: name,
        payment: _asString(data['payment']) ?? '',
        icon: _asString(data['icon']),
        handlingFeeFixed: _asInt(data['handling_fee_fixed']) ?? 0,
        handlingFeePercent: _asDouble(data['handling_fee_percent']) ?? 0,
        rawData: Map.unmodifiable(data),
      ),
    );
  }
  return List.unmodifiable(methods);
}

List<XboardOrderData> _parseOrdersSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  final rawOrders = switch (rawData) {
    final List<Object?> values => values,
    final Map<Object?, Object?> value when value['data'] is List =>
      value['data'] as List,
    _ => null,
  };
  if (rawOrders == null) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '订单列表接口响应缺少 data 数组',
      endpoint: endpoint,
    );
  }
  final orders = rawOrders
      .whereType<Map>()
      .map(_parseOrderData)
      .whereType<XboardOrderData>()
      .toList();
  orders.sort(
    (left, right) =>
        right.createdAtEpochSeconds.compareTo(left.createdAtEpochSeconds),
  );
  return List.unmodifiable(orders);
}

XboardOrderData _parseOrderDetailSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '订单详情接口响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final order = _parseOrderData(rawData);
  if (order == null) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '订单详情接口返回的数据不完整',
      endpoint: endpoint,
    );
  }
  return order;
}

XboardOrderData? _parseOrderData(Map<dynamic, dynamic> rawOrder) {
  final data = rawOrder.map((key, value) => MapEntry(key.toString(), value));
  final tradeNo = _asString(data['trade_no']);
  if (tradeNo == null) return null;
  final rawPlan = data['plan'];
  final plan = rawPlan is Map
      ? rawPlan.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  final rawPayment = data['payment'];
  final payment = rawPayment is Map
      ? rawPayment.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  return XboardOrderData(
    id: _asInt(data['id']) ?? 0,
    tradeNo: tradeNo,
    period: _asString(data['period']) ?? '',
    totalAmount: _asInt(data['total_amount']) ?? 0,
    status: _asInt(data['status']) ?? 0,
    createdAtEpochSeconds: _asEpochSeconds(data['created_at']) ?? 0,
    planName: _asString(plan['name']),
    paymentName: _asString(payment['name']),
    paidAtEpochSeconds: _asEpochSeconds(data['paid_at']),
    handlingAmount: _asInt(data['handling_amount']) ?? 0,
    discountAmount: _asInt(data['discount_amount']) ?? 0,
    balanceAmount: _asInt(data['balance_amount']) ?? 0,
    rawData: Map.unmodifiable(data),
  );
}

XboardUserInfo _parseUserInfoSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '个人资料接口响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final data = rawData.map((key, value) => MapEntry(key.toString(), value));
  final email = _asString(data['email']);
  if (email == null) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '个人资料接口未返回邮箱',
      endpoint: endpoint,
    );
  }
  final avatarText = _asString(data['avatar_url']);
  final avatarUrl = avatarText == null ? null : Uri.tryParse(avatarText);
  final expiredAt = _asInt(data['expired_at']);
  return XboardUserInfo(
    email: email,
    balance: _asInt(data['balance']) ?? 0,
    commissionBalance: _asInt(data['commission_balance']) ?? 0,
    remindExpire: _asBool(data['remind_expire']),
    remindTraffic: _asBool(data['remind_traffic']),
    avatarUrl:
        avatarUrl != null &&
            {'http', 'https'}.contains(avatarUrl.scheme) &&
            avatarUrl.host.isNotEmpty
        ? avatarUrl
        : null,
    telegramId: _asString(data['telegram_id']),
    planId: _asInt(data['plan_id']),
    expiredAtEpochSeconds: expiredAt == null || expiredAt <= 0
        ? null
        : expiredAt,
    rawData: Map.unmodifiable(data),
  );
}

XboardInviteSummary _parseInviteSummarySuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '邀请统计接口响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final data = rawData.map((key, value) => MapEntry(key.toString(), value));
  final rawCodes = data['codes'];
  final rawStat = data['stat'];
  if (rawCodes is! List || rawStat is! List || rawStat.length < 5) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '邀请统计接口返回的数据不完整',
      endpoint: endpoint,
    );
  }
  final codes = rawCodes
      .whereType<Map>()
      .map((rawCode) {
        final codeData = rawCode.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final code = _asString(codeData['code']);
        final createdAt = _asInt(codeData['created_at']);
        if (code == null || createdAt == null) return null;
        return XboardInviteCode(
          code: code,
          pageViews: _asInt(codeData['pv']) ?? 0,
          status: _asInt(codeData['status']) ?? 0,
          createdAtEpochSeconds: createdAt,
          rawData: Map.unmodifiable(codeData),
        );
      })
      .whereType<XboardInviteCode>()
      .toList(growable: false);
  return XboardInviteSummary(
    codes: List.unmodifiable(codes),
    registeredUsers: _asInt(rawStat[0]) ?? 0,
    confirmedCommission: _asInt(rawStat[1]) ?? 0,
    pendingCommission: _asInt(rawStat[2]) ?? 0,
    commissionRate: _asInt(rawStat[3]) ?? 0,
    availableCommission: _asInt(rawStat[4]) ?? 0,
  );
}

List<XboardCommissionRecord> _parseCommissionRecordsSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! List) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '佣金明细接口响应缺少 data 数组',
      endpoint: endpoint,
    );
  }
  return List.unmodifiable(
    rawData.whereType<Map>().map((rawRecord) {
      final data = rawRecord.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return XboardCommissionRecord(
        id: _asInt(data['id']) ?? 0,
        orderAmount: _asInt(data['order_amount']) ?? 0,
        tradeNo: _asString(data['trade_no']) ?? '',
        commissionAmount: _asInt(data['get_amount']) ?? 0,
        createdAtEpochSeconds: _asInt(data['created_at']) ?? 0,
        rawData: Map.unmodifiable(data),
      );
    }),
  );
}

XboardGuestConfig _parseGuestConfigSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '注册配置响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final data = rawData.map((key, value) => MapEntry(key.toString(), value));
  final suffixes = _normalizeEmailSuffixes(data['email_whitelist_suffix']);
  if (suffixes.isEmpty) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '注册配置未返回可用的邮箱后缀',
      endpoint: endpoint,
    );
  }
  return XboardGuestConfig(
    endpoint: endpoint,
    isEmailVerify: _asBool(data['is_email_verify']),
    isInviteForce: _asBool(data['is_invite_force']),
    emailWhitelistSuffix: List.unmodifiable(suffixes),
    rawData: Map.unmodifiable(data),
  );
}

XboardRegistrationResult _parseRegistrationSuccess(
  Uri endpoint,
  Map<String, Object?> response,
) {
  final rawData = response['data'];
  if (rawData is! Map) {
    throw XboardAuthException(
      failure: XboardAuthFailure.invalidResponse,
      message: '注册成功响应缺少 data 字段',
      endpoint: endpoint,
    );
  }
  final data = rawData.map((key, value) => MapEntry(key.toString(), value));
  final rawIsAdmin = data['is_admin'];
  return XboardRegistrationResult(
    endpoint: endpoint,
    token: _asString(data['token']),
    authData: _asString(data['auth_data']),
    isAdmin: rawIsAdmin == true || rawIsAdmin == 1 || rawIsAdmin == '1',
    rawData: Map.unmodifiable(data),
  );
}

class _XboardAuthData {
  const _XboardAuthData({
    required this.endpoint,
    required this.token,
    required this.authData,
    required this.isAdmin,
    required this.rawData,
  });

  final Uri endpoint;
  final String token;
  final String authData;
  final bool isAdmin;
  final Map<String, Object?> rawData;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

int? _asEpochSeconds(Object? value) {
  final numeric = _asInt(value);
  if (numeric != null) {
    if (numeric <= 0) return null;
    return numeric > 100000000000 ? numeric ~/ 1000 : numeric;
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _asString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

bool _asBool(Object? value) {
  return value == true || value == 1 || value?.toString() == '1';
}

List<String> _normalizeEmailSuffixes(Object? value) {
  if (value is! List) return const [];
  final suffixes = <String>[];
  for (final item in value) {
    if (item is! String) continue;
    final suffix = item.trim().replaceFirst(RegExp(r'^@+'), '');
    if (suffix.isNotEmpty) suffixes.add(suffix);
  }
  return suffixes;
}

List<String> _normalizeTags(Object? value) {
  Object? normalized = value;
  if (value is String) {
    try {
      normalized = jsonDecode(value);
    } catch (_) {
      normalized = value.split(',');
    }
  }
  final values = normalized is List ? normalized : [normalized];
  final tags = <String>[];
  for (final item in values) {
    final tag = _asString(item);
    if (tag != null && !tags.contains(tag)) tags.add(tag);
  }
  return tags;
}

String? _responseMessage(Map<String, Object?> response) {
  for (final key in const ['message', 'error']) {
    final value = response[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

Uri? _asXboardBaseEndpoint(Uri endpoint) {
  if (!{'http', 'https'}.contains(endpoint.scheme) || endpoint.host.isEmpty) {
    return null;
  }
  return endpoint.resolve('/');
}
